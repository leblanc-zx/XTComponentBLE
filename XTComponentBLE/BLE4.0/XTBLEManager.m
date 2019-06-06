//
//  XTBLEManager.m
//  SuntrontBlueTooth
//
//  Created by apple on 2017/7/28.
//  Copyright © 2017年 apple. All rights reserved.
//

#import "XTBLEManager.h"

typedef NS_ENUM(NSUInteger, TimerState) {
    TimerStateFinish = 0,   //正常结束
    TimerStateCancel = 1,   //被取消
};

typedef void(^TimerBlock)(TimerState state, NSError *error);

NSString *const TIMER_SCAN = @"TIMER_SCAN";
NSString *const TIMER_CONNECT = @"TIMER_CONNECT";
NSString *const TIMER_RECEIVE_DATA = @"TIMER_RECEIVE_DATA";
NSString *const SCAN_BLOCK = @"SCAN_BLOCK";
NSString *const SCAN_FINISHBLOCK = @"SCAN_FINISHBLOCK";
NSString *const CONNECT_SUCCESSBLOCK = @"CONNECT_SUCCESSBLOCK";
NSString *const CONNECT_FAILUREBLOCK = @"CONNECT_FAILUREBLOCK";
NSString *const CONNECTSTATE_DIDCHANGE_BLOCK = @"CONNECTSTATE_DIDCHANGE_BLOCK";
NSString *const SEND_PROGRESSDATA_BLOCK = @"SEND_PROGRESSDATA_BLOCK";
NSString *const SEND_STARTFILTER_BLOCK = @"SEND_STARTFILTER_BLOCK";
NSString *const SEND_ENDFILTER_BLOCK = @"SEND_ENDFILTER_BLOCK";
NSString *const SEND_RECEIVEDATASUCCESS_BLOCK = @"SEND_RECEIVEDATASUCCESS_BLOCK";
NSString *const SEND_RECEIVEDATAFAILURE_BLOCK = @"SEND_RECEIVEDATAFAILURE_BLOCK";
NSString *const CENTRALMANAGER_DIDUPDATESTATE_BLOCK = @"CENTRALMANAGER_DIDUPDATESTATE_BLOCK";

@interface XTBLEManager ()<CBCentralManagerDelegate, CBPeripheralDelegate>

/*----BlockDic----*/
@property (nonatomic, strong) NSMutableDictionary *blockDictionary;

/*----临时BlockDic----*/
@property (nonatomic, strong) NSMutableDictionary *blockTempDictionary;

/*----Timer----*/
@property (nonatomic, strong) NSMutableDictionary *timerDictionary;

/*----Scan----*/
@property (nonatomic, strong) NSMutableArray *BLEDevices;

/*----connect----*/
@property (nonatomic, strong) XTCBPeripheral *currentPeripheral;    //当前的蓝牙设备

/*----响应数据----*/
@property (nonatomic, strong) NSMutableData *responseData;          //总拼接
@property (nonatomic, strong) NSMutableData *progressSuccessData;   //过程中本次成功的数据拼接
@property (nonatomic, assign) int totalNum;                         //应该响应的总数据量
@property (nonatomic, assign) int progressSuccessNum;               //过程中成功接收到的数据量
@property (nonatomic, assign) int progressFailureNum;               //过程中失败的数据量

@property (nonatomic, assign) BOOL isBLEEnable;     //蓝牙是否可用


@end

@implementation XTBLEManager

static id _instace;

- (id)init
{
    static id obj;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ((obj = [super init])) {
            [self createBLEManager];
        }
    });
    self = obj;
    return self;
}

+ (id)allocWithZone:(struct _NSZone *)zone
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instace = [super allocWithZone:zone];
    });
    return _instace;
}

+ (id)sharedManager
{
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        _instace = [[self alloc] init];
    });
    
    return _instace;
}

/**
 创建蓝牙设备列表

 @return NSMutableArray
 */
- (NSMutableArray *)BLEDevices {
    if (!_BLEDevices) {
        _BLEDevices = [[NSMutableArray alloc] init];
    }
    return _BLEDevices;
}

/**
 创建timer字典

 @return NSMutableDictionary
 */
- (NSMutableDictionary *)timerDictionary {
    if (!_timerDictionary) {
        _timerDictionary = [[NSMutableDictionary alloc] init];
    }
    return _timerDictionary;
}

/**
 创建Block字典

 @return NSMutableDictionary
 */
- (NSMutableDictionary *)blockDictionary {
    if (!_blockDictionary) {
        _blockDictionary = [[NSMutableDictionary alloc] init];
    }
    return _blockDictionary;
}

/**
 创建临时Block字典
 
 @return NSMutableDictionary
 */
- (NSMutableDictionary *)blockTempDictionary {
    if (!_blockTempDictionary) {
        _blockTempDictionary = [[NSMutableDictionary alloc] init];
    }
    return _blockTempDictionary;
}

/**
 是否正在扫描

 @return 结果
 */
- (BOOL)isScanning {
    
    dispatch_source_t timer = [self getTimerWithIdentity:TIMER_SCAN];
    return timer ? YES : NO;
    
}

/**
 是否正在请求帧数据

 @return 结果
 */
- (BOOL)isRequesting {
    
    dispatch_source_t timer = [self getTimerWithIdentity:TIMER_RECEIVE_DATA];
    return timer ? YES : NO;
    
}

/**
 *  创建蓝牙管理
 */
- (void)createBLEManager {
    
    // 1.创建管理中心
    self.centralManager = [[CBCentralManager alloc]initWithDelegate:self queue:dispatch_get_main_queue() options:nil];
    // 2.蓝牙连接状态变化监听
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(XTCBPeripheralConnectStateChange:) name:XTCBPeripheralConnectStateChangeKey object:nil];
    
}

/**
 扫描蓝牙

 @param time 扫描时间 默认15秒
 @param scanBlock 返回扫描到的设备列表
 @param finishBlock 扫描结束
 */
- (void)scanWithTime:(float)time scanBlock:(ScanBlock)scanBlock finishBlock:(ScanFinishBlock)finishBlock {
    if (!self.isBLEEnable) {
        if (finishBlock) {
            finishBlock([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeBLENotEnable userInfo:@{NSLocalizedDescriptionKey:@"请打开蓝牙"}]);
        }
        return;
    }
    //正在扫描
    if (self.isScanning) {
        return;
    }
    
    //预备扫描
    if (scanBlock) {
        [self.blockDictionary setObject:scanBlock forKey:SCAN_BLOCK];
    }
    if (finishBlock) {
        [self.blockDictionary setObject:finishBlock forKey:SCAN_FINISHBLOCK];
    }
    float scanTime = time > 0 ? time : 15;
    [self.BLEDevices removeAllObjects];
    
    //开始扫描
    [self.centralManager scanForPeripheralsWithServices:nil options:nil];
    
    //开启定时器
    __weak typeof(self) weakSelf = self;
    [self openTimerWithIdentity:TIMER_SCAN timeDuration:scanTime block:^(TimerState state, NSError *error) {
        
        ScanFinishBlock cahcheFinishBlock = [self.blockDictionary objectForKey:SCAN_FINISHBLOCK];
        [self.blockDictionary removeObjectForKey:SCAN_BLOCK];
        
        if (state == TimerStateFinish) {
            //timer时间到了,扫描结束
            [weakSelf.centralManager stopScan];
            if (cahcheFinishBlock) {
                [self.blockDictionary removeObjectForKey:SCAN_FINISHBLOCK];
                cahcheFinishBlock(nil);
            }
        } else if (state == TimerStateCancel) {
            //timer被取消
            if (error.code == XTBLENSErrorCodeAutoCancelLastTimerTask) {
                //自动移除上次任务 do nothing
            } else {
                //扫描被取消了
                [self.centralManager stopScan];
                if (cahcheFinishBlock) {
                    [self.blockDictionary removeObjectForKey:SCAN_FINISHBLOCK];
                    cahcheFinishBlock(error);
                }
            }
        }
        
    }];
    
}

/**
 连接蓝牙设备
 
 @param peripheral 蓝牙设备
 @param timeOut 超时时间 默认15秒
 @param success 成功
 @param failure 失败
 */
- (void)connectWithPeripheral:(XTCBPeripheral *)peripheral timeOut:(float)timeOut success:(ConnectSuccessBlock)success failure:(ConnectFailureBlock)failure {
    
    if (!self.isBLEEnable) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeBLENotEnable userInfo:@{NSLocalizedDescriptionKey:@"请打开蓝牙"}]);
        }
        return;
    }
    
    //正在连接中,稍后再试
    if (self.currentPeripheral && self.currentPeripheral.connectState == XTCBPeripheralConnecting) {
        if (failure) {
            NSString *msg = [NSString stringWithFormat:@"正在连接%@,请稍后再试",self.currentPeripheral.peripheral.name];
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectFailed userInfo:@{NSLocalizedDescriptionKey:msg}]);
        }
        return;
    }
    
    if (!peripheral) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeNotDevice userInfo:@{NSLocalizedDescriptionKey:@"请选择要连接的蓝牙设备"}]);
        }
        return;
    }
    
    if ([peripheral.peripheral.identifier.UUIDString isEqualToString:self.currentPeripheral.peripheral.identifier.UUIDString] && self.currentPeripheral.connectState == XTCBPeripheralConnectSuccess) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectFailed userInfo:@{NSLocalizedDescriptionKey:@"已连接该蓝牙设备"}]);
        }
        return;
    }
    
    //预备连接
    float connectTimeOut = timeOut > 0 ? timeOut : 15;
    XTCBPeripheral *lastPeripheral = self.currentPeripheral;
    if (success) {
        [self.blockDictionary setObject:success forKey:CONNECT_SUCCESSBLOCK];
    }
    if (failure) {
        [self.blockDictionary setObject:failure forKey:CONNECT_FAILUREBLOCK];
    }
    
    self.currentPeripheral = peripheral;
    
    //自动断开上个连接
    if (lastPeripheral) {
        [self.centralManager cancelPeripheralConnection:lastPeripheral.peripheral];
        lastPeripheral.connectState = XTCBPeripheralNotConnected;
    }
    
    //开始连接
    [self.centralManager connectPeripheral:self.currentPeripheral.peripheral options:@{CBConnectPeripheralOptionNotifyOnConnectionKey:@YES,CBConnectPeripheralOptionNotifyOnDisconnectionKey:@YES,CBConnectPeripheralOptionNotifyOnNotificationKey:@YES}];
    peripheral.peripheral.delegate = self;
    
    self.currentPeripheral.connectState = XTCBPeripheralConnecting;
    
    //开启定时器
    __weak typeof(self) weakSelf = self;
    [self openTimerWithIdentity:TIMER_CONNECT timeDuration:connectTimeOut block:^(TimerState state, NSError *error) {
        if (state == TimerStateFinish) {
            //timer时间到了，连接超时
            weakSelf.currentPeripheral.connectState = XTCBPeripheralConnectTimeOut;
            [weakSelf.centralManager cancelPeripheralConnection:weakSelf.currentPeripheral.peripheral];
            [self.blockDictionary removeObjectForKey:CONNECT_SUCCESSBLOCK];
            ConnectFailureBlock cacheFailureBlock = [self.blockDictionary objectForKey:CONNECT_FAILUREBLOCK];
            if (cacheFailureBlock) {
                [self.blockDictionary removeObjectForKey:CONNECT_FAILUREBLOCK];
                cacheFailureBlock([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectTimeOut userInfo:@{NSLocalizedDescriptionKey:@"连接超时"}]);
            }
            
        } else if (state == TimerStateCancel) {
            //timer被取消
            if (error.code == XTBLENSErrorCodeAutoCancelLastTimerTask) {
                //自动移除上次任务 do nothing
            } else if (weakSelf.currentPeripheral.connectState == XTCBPeripheralNotConnected) {
                //未连接
                [weakSelf.centralManager cancelPeripheralConnection:weakSelf.currentPeripheral.peripheral];
                [self.blockDictionary removeObjectForKey:CONNECT_SUCCESSBLOCK];
                ConnectFailureBlock cacheFailureBlock = [self.blockDictionary objectForKey:CONNECT_FAILUREBLOCK];
                if (cacheFailureBlock) {
                    [self.blockDictionary removeObjectForKey:CONNECT_FAILUREBLOCK];
                    cacheFailureBlock([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectFailed userInfo:@{NSLocalizedDescriptionKey: @"代码异常"}]);
                }
            } else if (weakSelf.currentPeripheral.connectState == XTCBPeripheralConnecting) {
                //连接中
                [weakSelf.centralManager cancelPeripheralConnection:weakSelf.currentPeripheral.peripheral];
                [self.blockDictionary removeObjectForKey:CONNECT_SUCCESSBLOCK];
                ConnectFailureBlock cacheFailureBlock = [self.blockDictionary objectForKey:CONNECT_FAILUREBLOCK];
                if (cacheFailureBlock) {
                    [self.blockDictionary removeObjectForKey:CONNECT_FAILUREBLOCK];
                    cacheFailureBlock([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectFailed userInfo:@{NSLocalizedDescriptionKey: @"代码异常"}]);
                }
            } else if (weakSelf.currentPeripheral.connectState == XTCBPeripheralConnectingCanceled) {
                //连接中被取消
                [weakSelf.centralManager cancelPeripheralConnection:weakSelf.currentPeripheral.peripheral];
                [self.blockDictionary removeObjectForKey:CONNECT_SUCCESSBLOCK];
                ConnectFailureBlock cacheFailureBlock = [self.blockDictionary objectForKey:CONNECT_FAILUREBLOCK];
                if (cacheFailureBlock) {
                    [self.blockDictionary removeObjectForKey:CONNECT_FAILUREBLOCK];
                    cacheFailureBlock(error);
                }
            } else if (weakSelf.currentPeripheral.connectState == XTCBPeripheralConnectFailed) {
                //连接失败
                [weakSelf.centralManager cancelPeripheralConnection:weakSelf.currentPeripheral.peripheral];
                [self.blockDictionary removeObjectForKey:CONNECT_SUCCESSBLOCK];
                ConnectFailureBlock cacheFailureBlock = [self.blockDictionary objectForKey:CONNECT_FAILUREBLOCK];
                if (cacheFailureBlock) {
                    [self.blockDictionary removeObjectForKey:CONNECT_FAILUREBLOCK];
                    cacheFailureBlock(error);
                }
            } else if (weakSelf.currentPeripheral.connectState == XTCBPeripheralConnectSuccess) {
                //连接成功了
                [self.blockDictionary removeObjectForKey:CONNECT_FAILUREBLOCK];
                ConnectSuccessBlock cahceSuccessBlock = [self.blockDictionary objectForKey:CONNECT_SUCCESSBLOCK];
                if (cahceSuccessBlock) {
                    [self.blockDictionary removeObjectForKey:CONNECT_SUCCESSBLOCK];
                    cahceSuccessBlock();
                }
            } else if (weakSelf.currentPeripheral.connectState == XTCBPeripheralDidDisconnect) {
                //连接成功后,断开连接
                [weakSelf.centralManager cancelPeripheralConnection:weakSelf.currentPeripheral.peripheral];
                [self.blockDictionary removeObjectForKey:CONNECT_SUCCESSBLOCK];
                ConnectFailureBlock cacheFailureBlock = [self.blockDictionary objectForKey:CONNECT_FAILUREBLOCK];
                if (cacheFailureBlock) {
                    [self.blockDictionary removeObjectForKey:CONNECT_FAILUREBLOCK];
                    cacheFailureBlock(error);
                }
            }
        }
    }];
    
}

/**
 重新连接蓝牙设备
 
 @param timeOut 超时时间 默认15秒
 @param success 成功
 @param failure 失败
 */
- (void)reConnectWithTimeOut:(float)timeOut success:(ConnectSuccessBlock)success failure:(ConnectFailureBlock)failure {
    [self connectWithPeripheral:self.currentPeripheral timeOut:timeOut success:success failure:failure];
}

/**
 发送数据
 
 @param data 帧数据
 @param startFilter 开始条件(YES:过滤成功; NO:过滤等待)
 @param endFilter 结束条件(YES:过滤成功; NO:过滤等待)
 @param success 处理并拼接后的帧数据
 @param failure 出错
 */
- (void)sendSimpleData:(NSData *)data startFilter:(BOOL(^)(NSData *receiveData))startFilter endFilter:(BOOL(^)(NSData *JointData))endFilter success:(ReceiveDataSuccessBlock)success failure:(ReceiveDataFailureBlock)failure {
    
    StartFilterData startFilterBlock = nil;
    if (startFilter) {
        startFilterBlock = ^XTBLEFilterResult(NSData *receiveData) {
            BOOL result = startFilter(receiveData);
            return result == YES ? XTBLEFilterResultSuccess : XTBLEFilterResultWait;
        };
    }
    
    EndFilterData endFilterBlock = nil;
    if (endFilter) {
        endFilterBlock = ^XTBLEFilterResult(NSData *JointData) {
            BOOL result = endFilter(JointData);
            return result == YES ? XTBLEFilterResultSuccess : XTBLEFilterResultWait;
        };
    }
    
    [self sendData:data startFilter:startFilterBlock endFilter:endFilterBlock success:success failure:failure];
}

/**
 发送数据
 
 @param data 帧数据
 @param startFilter 开始条件
 @param endFilter 结束条件
 @param success 处理并拼接后的帧数据
 @param failure 出错
 */
- (void)sendData:(NSData *)data startFilter:(StartFilterData)startFilter endFilter:(EndFilterData)endFilter success:(ReceiveDataSuccessBlock)success failure:(ReceiveDataFailureBlock)failure {
    [self sendData:data timeOut:10 timeInterval:0 startFilter:startFilter endFilter:endFilter success:success failure:failure];
}

/**
 发送数据
 
 @param data 帧数据
 @param timeOut 超时时间
 @param timeInterval 发送帧时间间隔 0.0~1.0之间
 @param startFilter 开始条件
 @param endFilter 结束条件
 @param success 处理并拼接后的帧数据
 @param failure 出错
 */
- (void)sendData:(NSData *)data timeOut:(float)timeOut timeInterval:(float)timeInterval startFilter:(StartFilterData)startFilter endFilter:(EndFilterData)endFilter success:(ReceiveDataSuccessBlock)success failure:(ReceiveDataFailureBlock)failure {
    [self sendData:data receiveNum:1 timeOut:timeOut timeInterval:timeInterval startFilter:startFilter endFilter:endFilter progress:nil success:success failure:failure];
}

/**
 发送数据
 
 @param data 帧数据
 @param receiveNum 接收帧数据个数
 @param timeOut 超时时间
 @param timeInterval 发送帧时间间隔 0.0~1.0之间
 @param startFilter 开始条件
 @param endFilter 结束条件
 @param progress 过程(可能发一次帧，接收多个结果)
 @param success 处理并拼接后的帧数据
 @param failure 出错
 */
- (void)sendData:(NSData *)data receiveNum:(int)receiveNum timeOut:(float)timeOut timeInterval:(float)timeInterval startFilter:(StartFilterData)startFilter endFilter:(EndFilterData)endFilter progress:(ReceiveDataProgressBlock)progress success:(ReceiveDataSuccessBlock)success failure:(ReceiveDataFailureBlock)failure {
    [self sendData:data receiveNum:receiveNum characteristic:self.currentPeripheral.writeCharacteristic timeOut:timeOut timeInterval:timeInterval startFilter:startFilter endFilter:endFilter progress:progress success:success failure:failure];
}

/**
 发送数据

 @param data 帧数据
 @param receiveNum 接收帧数据个数
 @param timeOut 超时时间
 @param timeInterval 发送帧时间间隔 0.0~1.0之间
 @param startFilter 开始条件
 @param endFilter 结束条件
 @param progress 过程(可能发一次帧，接收多个结果)
 @param success 处理并拼接后的帧数据
 @param failure 出错
 */
- (void)sendData:(NSData *)data receiveNum:(int)receiveNum characteristic:(CBCharacteristic *)characteristic timeOut:(float)timeOut timeInterval:(float)timeInterval startFilter:(StartFilterData)startFilter endFilter:(EndFilterData)endFilter progress:(ReceiveDataProgressBlock)progress success:(ReceiveDataSuccessBlock)success failure:(ReceiveDataFailureBlock)failure {
    
    if (!self.isBLEEnable) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeBLENotEnable userInfo:@{NSLocalizedDescriptionKey:@"请打开蓝牙"}]);
        }
        return;
    }
    
    if (self.currentPeripheral.peripheral.state != CBPeripheralStateConnected) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeNotConnect userInfo:@{NSLocalizedDescriptionKey: @"请先连接蓝牙"}]);
        }
        return;
    }
    if (self.currentPeripheral.connectState != XTCBPeripheralConnectSuccess) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeSendFailed userInfo:@{NSLocalizedDescriptionKey: @"没有发现写特性"}]);
        }
        return;
    }
    if (data.length > LimitLength && timeInterval > 1) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeSendFailed userInfo:@{NSLocalizedDescriptionKey: @"每帧发送时间间隔不能大于1秒"}]);
        }
        return;
    }
    
    //预备发送数据
    self.responseData = [[NSMutableData alloc] init];
    self.progressSuccessData = [[NSMutableData alloc] init];
    
    //应该响应数据总数
    self.totalNum = receiveNum;
    self.progressSuccessNum = 0;
    self.progressFailureNum = 0;
    
    //清空临时字典
    [self.blockTempDictionary removeAllObjects];
    
    //清空blockDictionary
    [self.blockDictionary removeObjectForKey:SEND_STARTFILTER_BLOCK];
    [self.blockDictionary removeObjectForKey:SEND_ENDFILTER_BLOCK];
    [self.blockDictionary removeObjectForKey:SEND_PROGRESSDATA_BLOCK];
    [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATASUCCESS_BLOCK];
    [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
    
    if (startFilter) {
        [self.blockDictionary setObject:startFilter forKey:SEND_STARTFILTER_BLOCK];
    }
    if (endFilter) {
        [self.blockDictionary setObject:endFilter forKey:SEND_ENDFILTER_BLOCK];
    }
    if (progress) {
        [self.blockDictionary setObject:progress forKey:SEND_PROGRESSDATA_BLOCK];
    }
    if (success) {
        [self.blockDictionary setObject:success forKey:SEND_RECEIVEDATASUCCESS_BLOCK];
    }
    if (failure) {
        [self.blockDictionary setObject:failure forKey:SEND_RECEIVEDATAFAILURE_BLOCK];
    }
    
    //开始发送
    CBCharacteristicProperties properties = characteristic.properties;
    NSError *error;
    
    if (properties & CBCharacteristicPropertyWrite) {
        
        if (data.length > LimitLength) {
            
            NSInteger index = 0;
            for (index = 0; index < data.length - LimitLength; index += LimitLength) {
                NSData *subData = [data subdataWithRange:NSMakeRange(index, LimitLength)];
                [self.currentPeripheral.peripheral writeValue:subData forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
                [self sleepWithTime:timeInterval];
            }
            NSData *leftData = [data subdataWithRange:NSMakeRange(index, data.length - index)];
            if (leftData) {
                [self.currentPeripheral.peripheral writeValue:leftData forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
            }
            
        } else {
            [self.currentPeripheral.peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
        }
        
        
    } else if (properties & CBCharacteristicPropertyWriteWithoutResponse) {
        
        if (data.length > LimitLength) {
            
            NSInteger index = 0;
            for (index = 0; index < data.length - LimitLength; index += LimitLength) {
                NSData *subData = [data subdataWithRange:NSMakeRange(index, LimitLength)];
                [self.currentPeripheral.peripheral writeValue:subData forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
                [self sleepWithTime:timeInterval];
            }
            NSData *leftData = [data subdataWithRange:NSMakeRange(index, data.length - index)];
            if (leftData) {
                [self.currentPeripheral.peripheral writeValue:leftData forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
            }
            
        } else {
            [self.currentPeripheral.peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
        }
        
    } else {
        error = [NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeSendFailed userInfo:@{NSLocalizedDescriptionKey: @"特性不可写"}];
    }
    
    if (error) {
        [self.blockDictionary removeObjectForKey:SEND_STARTFILTER_BLOCK];
        [self.blockDictionary removeObjectForKey:SEND_ENDFILTER_BLOCK];
        [self.blockDictionary removeObjectForKey:SEND_PROGRESSDATA_BLOCK];
        [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATASUCCESS_BLOCK];
        ReceiveDataFailureBlock cacheReceiveDataFailure = [self.blockDictionary objectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
        if (cacheReceiveDataFailure) {
            [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
            cacheReceiveDataFailure(error);
        }
        return;
    }
    
    float duration = timeOut > 0 ? timeOut : 10;
    [self openTimerWithIdentity:TIMER_RECEIVE_DATA timeDuration:duration block:^(TimerState state, NSError *error) {
        
        if (state == TimerStateFinish) {
            //timer正常结束，超时了
            [self.blockDictionary removeObjectForKey:SEND_STARTFILTER_BLOCK];
            [self.blockDictionary removeObjectForKey:SEND_ENDFILTER_BLOCK];
            [self.blockDictionary removeObjectForKey:SEND_PROGRESSDATA_BLOCK];
            [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATASUCCESS_BLOCK];
            ReceiveDataFailureBlock cacheReceiveDataFailure = [self.blockDictionary objectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
            if (cacheReceiveDataFailure) {
                [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
                cacheReceiveDataFailure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeReceiveTimeOut userInfo:@{NSLocalizedDescriptionKey: @"请求超时"}]);
            }
        }
        if (state == TimerStateCancel) {
            //timer被取消了
            if (error.code == XTBLENSErrorCodeAutoCancelLastTimerTask) {
                //自动移除上次任务 do nothing
            } else if (error) {
                //数据接收异常 || 数据接收被取消
                [self.blockDictionary removeObjectForKey:SEND_STARTFILTER_BLOCK];
                [self.blockDictionary removeObjectForKey:SEND_ENDFILTER_BLOCK];
                [self.blockDictionary removeObjectForKey:SEND_PROGRESSDATA_BLOCK];
                [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATASUCCESS_BLOCK];
                ReceiveDataFailureBlock cacheReceiveDataFailure = [self.blockDictionary objectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
                if (cacheReceiveDataFailure) {
                    [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
                    cacheReceiveDataFailure(error);
                }
            } else {
                //接收数据完成
                [self.blockDictionary removeObjectForKey:SEND_STARTFILTER_BLOCK];
                [self.blockDictionary removeObjectForKey:SEND_ENDFILTER_BLOCK];
                [self.blockDictionary removeObjectForKey:SEND_PROGRESSDATA_BLOCK];
                [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
                ReceiveDataSuccessBlock cacheReceiveDataSuccess = [self.blockDictionary objectForKey:SEND_RECEIVEDATASUCCESS_BLOCK];
                if (cacheReceiveDataSuccess) {
                    [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATASUCCESS_BLOCK];
                    cacheReceiveDataSuccess(self.responseData);
                }
            }
        }
    }];
    
}

/**
 取消扫描蓝牙设备
 */
- (void)cancelScan {
    [self cancelTimerWithIdentity:TIMER_SCAN error:[NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeScanCanceled userInfo:@{NSLocalizedDescriptionKey: @"扫描被取消"}]];
}

/**
 取消蓝牙连接
 */
- (void)cancelConnect {
    
    //取消正在连接的蓝牙
    [self cancelConnecting];
    //断开已连接的蓝牙
    [self disConnected];
    
}

/**
 取消正在连接的蓝牙
 */
- (void)cancelConnecting {
    
    if (self.currentPeripheral.connectState == XTCBPeripheralNotConnected ||
        self.currentPeripheral.connectState == XTCBPeripheralConnectFailed ||
        self.currentPeripheral.connectState == XTCBPeripheralConnectTimeOut ||
        self.currentPeripheral.connectState == XTCBPeripheralConnectingCanceled ||
        self.currentPeripheral.connectState == XTCBPeripheralConnectSuccess ||
        self.currentPeripheral.connectState == XTCBPeripheralDidDisconnect) {
        //【未连接、连接失败、连接超时、连接中已被取消、连接成功、连接成功后断开连接】不做处理
        return;
    }
    if (self.currentPeripheral.connectState == XTCBPeripheralConnecting) {
        //连接中
        self.currentPeripheral.connectState = XTCBPeripheralConnectingCanceled;
        [self cancelTimerWithIdentity:TIMER_CONNECT error:[NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectCanceled userInfo:@{NSLocalizedDescriptionKey: @"连接被取消"}]];
    }
}

/**
 断开已连接的蓝牙
 */
- (void)disConnected {
    if (self.currentPeripheral.connectState == XTCBPeripheralConnectSuccess) {
        //连接成功
        if (self.isBLEEnable) {
            [self.centralManager cancelPeripheralConnection:self.currentPeripheral.peripheral];
        } else {
            self.currentPeripheral.connectState = XTCBPeripheralNotConnected;
        }
    }
}

/**
 取消接收数据
 */
- (void)cancelReceiveData {
    [self cancelTimerWithIdentity:TIMER_RECEIVE_DATA error:[NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeReceiveCanceled userInfo:@{NSLocalizedDescriptionKey: @"请求被取消"}]];
}

/**
 取消接收数据
 
 @param error 错误
 */
- (void)cancelReceiveData:(NSError *)error {
    if (!error) {
        [self cancelReceiveData];
    } else {
        [self cancelTimerWithIdentity:TIMER_RECEIVE_DATA error:error];
    }
}

/**
 关闭Manager
 */
- (void)doClose {
    [self cancelScan];
    [self cancelConnect];
    [self cancelReceiveData];
}

/**
 蓝牙连接状态变化(连接/断开)监听
 
 @param connectStateDidChangeBlock 回调
 */
- (void)setBlockOnConnectStateDidChange:(ConnectStateDidChangeBlock)connectStateDidChangeBlock {
    [self.blockDictionary setObject:connectStateDidChangeBlock forKey:CONNECTSTATE_DIDCHANGE_BLOCK];
}

- (void)XTCBPeripheralConnectStateChange:(NSNotification *)noti {
    
    XTCBPeripheral *peripheral = noti.object;
    
    if (self.currentPeripheral && self.currentPeripheral == peripheral) {
        
        XTCBPeripheralConnectState connectState = peripheral.connectState;
        
        ConnectStateDidChangeBlock chacheStateDidChangeBlock = [self.blockDictionary objectForKey:CONNECTSTATE_DIDCHANGE_BLOCK];
        
        if (chacheStateDidChangeBlock) {
            chacheStateDidChangeBlock(connectState);
        }
    }
}

/**
 设备状态改变的委托
 
 @param block 状态改变 回调
 */
- (void)setBlockOnCentralManagerDidUpdateState:(CentralManagerDidUpdateState)block {
    [self.blockDictionary setObject:block forKey:CENTRALMANAGER_DIDUPDATESTATE_BLOCK];
}

/**
 修改设备名称
 
 @param deviceName 新设备名
 @param success success
 @param failure error
 */
- (void)changeDeviceName:(NSString *)deviceName success:(void (^)(void))success failure:(void (^)(NSError *error))failure {
    NSData *requestData = [deviceName dataUsingEncoding:NSUTF8StringEncoding];
    [self sendData:requestData receiveNum:1 characteristic:self.currentPeripheral.nameCharacteristic timeOut:10 timeInterval:0 startFilter:nil endFilter:nil progress:nil success:^(NSData *data) {
        if (success) {
            success();
        }
    } failure:^(NSError *error) {
        if (failure) {
            failure(error);
        }
    }];
}

#pragma -mark 倒计时

/**
 开启定时器

 @param identity 标识
 @param duration 定时时长
 @param block 回调
 */
- (void)openTimerWithIdentity:(NSString *)identity timeDuration:(float)duration block:(TimerBlock)block {
    
    if (identity.length == 0) {
        return;
    }
    
    //创建线程队列
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    //移除上次任务
    dispatch_source_t timer = [self.timerDictionary objectForKey:identity];
    if (timer) {
        NSError *error = [NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeAutoCancelLastTimerTask userInfo:@{NSLocalizedDescriptionKey: @"移除上次任务"}];
        [self cancelTimerWithIdentity:identity error:error];
    }
    
    //创建dispatch_source_t的timer
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_resume(timer);
    
    //缓存timer & block
    [self.timerDictionary setObject:timer forKey:identity];
    [self.blockDictionary setObject:block forKey:identity];
    
    //设置首次执行事件、执行间隔和精确度(默认为0.1s)
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, duration * NSEC_PER_SEC), duration * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    
    
    __weak typeof(self) weakSelf = self;
    //时间间隔到点时执行block
    dispatch_source_set_event_handler(timer, ^{
        
        //取消timer
        [weakSelf.timerDictionary removeObjectForKey:identity];
        dispatch_source_cancel(timer);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            TimerBlock cacheBlock = [self.blockDictionary objectForKey:identity];
            if (cacheBlock) {
                [weakSelf.blockDictionary removeObjectForKey:identity];
                cacheBlock(TimerStateFinish, nil);
            }
        });
        
    });
    
}

/**
 取消timer
 */
- (void)cancelTimerWithIdentity:(NSString *)identity error:(NSError *)error {
    
    dispatch_source_t timer = [self.timerDictionary objectForKey:identity];
    if (timer) {
        dispatch_source_cancel(timer);
        [self.timerDictionary removeObjectForKey:identity];
        
        TimerBlock cacheBlock = [self.blockDictionary objectForKey:identity];
        if (cacheBlock) {
            [self.blockDictionary removeObjectForKey:identity];
            cacheBlock(TimerStateCancel, error);
        }
        
    }
    
}

/**
 获取timer
 */
- (dispatch_source_t)getTimerWithIdentity:(NSString *)identity {
    dispatch_source_t timer = [self.timerDictionary objectForKey:identity];
    return timer;
}

#pragma -mark CBCentralManagerDelegate
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    //NSLog(@"===update===%@",central);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (central.state == CBCentralManagerStatePoweredOn) {
            //设备打开成功
            self.isBLEEnable = YES;
        } else {
            self.isBLEEnable = NO;
            [self doClose];
        }
        
        CentralManagerDidUpdateState cacheBlock = [self.blockDictionary objectForKey:CENTRALMANAGER_DIDUPDATESTATE_BLOCK];
        if (cacheBlock) {
            cacheBlock(central);
        }
    });
    
}

//扫描到蓝牙外设后，会调用CBCentralManagerDelegate的这个代理方法：
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(nonnull CBPeripheral *)peripheral advertisementData:(nonnull NSDictionary<NSString *,id> *)advertisementData RSSI:(nonnull NSNumber *)RSSI {
   
    [self insertList:peripheral advertisementData:advertisementData RSSI:RSSI];
  
}

//连接成功
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    
    //查找服务
    [peripheral discoverServices:nil];
    
}

//连接失败
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    
    self.currentPeripheral.connectState = XTCBPeripheralConnectFailed;
    [self cancelTimerWithIdentity:TIMER_CONNECT error:error];
    
}

//蓝牙断开监听
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    
    if ([peripheral.identifier.UUIDString isEqualToString:self.currentPeripheral.peripheral.identifier.UUIDString]) {
        //断开的是当前连接的
        if (self.currentPeripheral.connectState == XTCBPeripheralConnectTimeOut ||
            self.currentPeripheral.connectState == XTCBPeripheralConnectFailed ||
            self.currentPeripheral.connectState == XTCBPeripheralNotConnected ||
            self.currentPeripheral.connectState == XTCBPeripheralConnecting ||
            self.currentPeripheral.connectState == XTCBPeripheralConnectingCanceled ||
            self.currentPeripheral.connectState == XTCBPeripheralDidDisconnect) {
            //【连接超时、连接失败、未连接、连接中、连接中已被取消、连接成功后已断开连接】都不需要处理
            return;
        }
        
        //处于连接成功状态的，才进行断开处理
        self.currentPeripheral.connectState = XTCBPeripheralDidDisconnect;
        NSError *blockError = [NSError errorWithDomain:@"错误" code:110 userInfo:@{NSLocalizedDescriptionKey: @"断开连接"}];
        
        //取消数据请求
        if (self.isRequesting) {
            [self cancelReceiveData:blockError];
        }
        
    }
    
}

#pragma -mark CBPeripheralDelegate
//发现服务
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    
    if (error)
    {
        self.currentPeripheral.connectState = XTCBPeripheralConnectFailed;
        [self cancelTimerWithIdentity:TIMER_CONNECT error:error];
        return;
    }
    
    CBUUID *cbUUID = [CBUUID UUIDWithString:WRITE_CHARACTERISTICS];
    CBUUID *cbUUID2 = [CBUUID UUIDWithString:NOTIFIY_CHARACTERISTICS];
    CBUUID *cbUUID3 = [CBUUID UUIDWithString:CHANGENAME_CHARACTERISTICS];
    
    for (CBService *service in peripheral.services) {
        //如果我们知道要查询的特性的CBUUID，可以在参数一中传入CBUUID数组。
        [peripheral discoverCharacteristics:@[cbUUID,cbUUID2,cbUUID3] forService:service];
        //[peripheral discoverCharacteristics:nil forService:service];
    }
    
}

//服务中的特性
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    
    if (error) {
        self.currentPeripheral.connectState = XTCBPeripheralConnectFailed;
        [self cancelTimerWithIdentity:TIMER_CONNECT error:error];
        return;
    }
    
    for (CBCharacteristic *character in service.characteristics) {
        
        if ([character.UUID.UUIDString isEqualToString:WRITE_CHARACTERISTICS]) {
            //发现写特性
            self.currentPeripheral.writeCharacteristic = character;
        }
        
        if ([character.UUID.UUIDString isEqualToString:NOTIFIY_CHARACTERISTICS]) {
            //发现通知特性
            self.currentPeripheral.notifiyCharacteristic = character;
            
            //注册通知
            [peripheral setNotifyValue:YES forCharacteristic:character];
            
        }
        
        if ([character.UUID.UUIDString isEqualToString:CHANGENAME_CHARACTERISTICS]) {
            //发现改名字特性
            self.currentPeripheral.nameCharacteristic = character;
        }
        
        if (self.currentPeripheral.writeCharacteristic && self.currentPeripheral.notifiyCharacteristic) {
            
            self.currentPeripheral.connectState = XTCBPeripheralConnectSuccess;
            [self cancelTimerWithIdentity:TIMER_CONNECT error:nil];
            
        }
    }
    
    
}

//通知方法
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(nonnull CBCharacteristic *)characteristic error:(nullable NSError *)error {
    if (error) {
        return;
    }
    
    CBCharacteristicProperties properties = characteristic.properties;
    if (properties & CBCharacteristicPropertyRead) {
        //如果具备读特性，即可以读取特性的value
        [peripheral readValueForCharacteristic:characteristic];
    }
    
}

// 读取新值的结果
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        [self cancelTimerWithIdentity:TIMER_RECEIVE_DATA error:error];
    }
    
    //progress
    ReceiveDataProgressBlock progressBlock = [self.blockDictionary objectForKey:SEND_PROGRESSDATA_BLOCK];
    
    //开始拼接条件
    StartFilterData startFilterDataBlock = [self.blockDictionary objectForKey:SEND_STARTFILTER_BLOCK];
    if (startFilterDataBlock) {
        //设置了条件
        XTBLEFilterResult startFilterResult = startFilterDataBlock(characteristic.value);
        if (startFilterResult == XTBLEFilterResultWait) {
            //等待
            return;
        } else if (startFilterResult == XTBLEFilterResultFailure) {
            //开头过滤失败
            NSError *startFilterError = [NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeStartFilterFailed userInfo:@{NSLocalizedDescriptionKey: @"开头过滤失败"}];
            self.progressFailureNum ++;
            if (progressBlock) {
                progressBlock(self.totalNum, self.progressSuccessNum, self.progressFailureNum, nil, startFilterError);
            }
            if (self.totalNum <= self.progressFailureNum + self.progressSuccessNum) {
                //过滤到最后一条数据了，取消接收数据
                [self cancelReceiveData:startFilterError];
            }
            return;
        } else {
            //开头过滤成功，往下执行
            [self.blockDictionary removeObjectForKey:SEND_STARTFILTER_BLOCK];//开始条件暂时不需要了
            [self.blockTempDictionary setObject:startFilterDataBlock forKey:SEND_STARTFILTER_BLOCK];//存入临时字典中
        }
    }
    
    /*---可以开始拼接了：未设置开始条件 or 条件已通过---*/
    
    //拼接数据
    [self.progressSuccessData appendData:characteristic.value];
    
    //结束拼接条件
    EndFilterData endFilterDataBlock = [self.blockDictionary objectForKey:SEND_ENDFILTER_BLOCK];
    if (endFilterDataBlock) {
        //设置了条件
        XTBLEFilterResult endFilterResult = endFilterDataBlock(self.progressSuccessData);
        if (endFilterResult == XTBLEFilterResultWait) {
            //等待
            return;
        } else if (endFilterResult == XTBLEFilterResultFailure) {
            //结尾过滤失败
            NSError *endFilterError = [NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeStartFilterFailed userInfo:@{NSLocalizedDescriptionKey: @"结尾过滤失败"}];
            self.progressFailureNum ++;
            if (progressBlock) {
                progressBlock(self.totalNum, self.progressSuccessNum, self.progressFailureNum, nil, endFilterError);
            }
            if (self.totalNum <= self.progressFailureNum + self.progressSuccessNum) {
                //过滤到最后一条数据了，取消接收数据
                [self cancelReceiveData:endFilterError];
            }
            return;
        } else {
            //结尾过滤成功，往下执行
            [self.blockDictionary removeObjectForKey:SEND_ENDFILTER_BLOCK];//结尾条件暂时不需要了
            [self.blockTempDictionary setObject:endFilterDataBlock forKey:SEND_ENDFILTER_BLOCK];//存入临时字典中
        }
    }
    
    //一条数据拼接完成了
    [self.responseData appendData:self.progressSuccessData];
    NSData *thisData = self.progressSuccessData;
    self.progressSuccessData = [[NSMutableData alloc] init];
    
    if (endFilterDataBlock) {
        //设置了条件，并且已经通过了
        self.progressSuccessNum ++;
        
        if (progressBlock) {
            progressBlock(self.totalNum, self.progressSuccessNum, self.progressFailureNum, thisData, nil);
        }
        
        if (self.totalNum <= self.progressSuccessNum + self.progressFailureNum) {
            //结束了
            [self receiveDataFinish:nil];
        } else {
            //还要接收下一条数据
            StartFilterData tempStart = [self.blockTempDictionary objectForKey:SEND_STARTFILTER_BLOCK];
            if (tempStart) {
                [self.blockDictionary setObject:tempStart forKey:SEND_STARTFILTER_BLOCK];
            }
            EndFilterData tempEnd = [self.blockTempDictionary objectForKey:SEND_ENDFILTER_BLOCK];
            if (tempEnd) {
                [self.blockDictionary setObject:tempEnd forKey:SEND_ENDFILTER_BLOCK];
            }
        }
    } else {
        //未设置条件
        //如果0.5秒内未再接收到数据，那么就结束了
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
        [self performSelector:@selector(receiveDataFinish:) withObject:characteristic afterDelay:0.5];
    }
    
    
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (characteristic == self.currentPeripheral.nameCharacteristic) {
        //修改名字特性
        [self receiveDataFinish:nil];
    }
    
}

#pragma -mark private
/**
 收到数据回调
 */
- (void)receiveDataFinish:(CBCharacteristic *)characteristic {
    //数据接收完毕
    [self cancelTimerWithIdentity:TIMER_RECEIVE_DATA error:nil];
}

//插入dataList
-(void)insertList:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI{
    
    if (self.BLEDevices.count == 0) {
        XTCBPeripheral *model = [[XTCBPeripheral alloc] init];
        model.peripheral = peripheral;
        model.advertisementData = advertisementData;
        model.RSSI = RSSI;
        [self.BLEDevices addObject:model];
    } else {
        BOOL isExist = NO;
        for (int i = 0; i < self.BLEDevices.count; i++) {
            XTCBPeripheral *oldModel = [self.BLEDevices objectAtIndex:i];
            if ([oldModel.peripheral.identifier.UUIDString isEqualToString:peripheral.identifier.UUIDString]) {
                isExist = YES;
                XTCBPeripheral *model = [[XTCBPeripheral alloc] init];
                model.peripheral = peripheral;
                model.advertisementData = advertisementData;
                model.RSSI = RSSI;
                [self.BLEDevices replaceObjectAtIndex:i withObject:model];
            }
        }
        
        if (!isExist) {
            XTCBPeripheral *model = [[XTCBPeripheral alloc] init];
            model.peripheral = peripheral;
            model.advertisementData = advertisementData;
            model.RSSI = RSSI;
            [self.BLEDevices addObject:model];
        }
    }
    
    for (int i = 0; i < self.BLEDevices.count; i ++) {
        XTCBPeripheral *model = self.BLEDevices[i];
        if ([model.peripheral.identifier.UUIDString isEqualToString:self.currentPeripheral.peripheral.identifier.UUIDString]) {
            model.connectState = self.currentPeripheral.connectState;
        } else {
            model.connectState = XTCBPeripheralNotConnected;
        }
    }
    
    ScanBlock cacheScanBlcok = [self.blockDictionary objectForKey:SCAN_BLOCK];
    if (cacheScanBlcok) {
        cacheScanBlcok(self.BLEDevices);
    }
}


/**
 保存蓝牙设备

 @param xtPeripheral 蓝牙设备
 */
- (void)saveXTPeripheral:(XTCBPeripheral *)xtPeripheral {
    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
    NSArray *array = [def objectForKey:@"XTCBPeripheral.peripheral.save.key"];
    if (array.count > 0) {
        for (int i = 0; i < array.count; i ++) {
            NSString *identify = array[i];
            if ([identify isEqualToString:xtPeripheral.peripheral.identifier.UUIDString]) {
                return;
            }
        }
    }
    NSMutableArray *tempArray = [[NSMutableArray alloc] initWithArray:array];
    [tempArray addObject:xtPeripheral.peripheral.identifier.UUIDString];
    [def setObject:tempArray forKey:@"XTCBPeripheral.peripheral.save.key"];
    [def synchronize];
}


/**
 移除已保存的蓝牙设备

 @param xtPeripheral 蓝牙设备
 */
- (void)removeSavedXTPeripheral:(XTCBPeripheral *)xtPeripheral {
    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
    NSArray *array = [def objectForKey:@"XTCBPeripheral.peripheral.save.key"];
    
    if (array.count > 0) {
        
        NSMutableArray *tempArray = [[NSMutableArray alloc] initWithArray:array];
        
        for (int i = 0; i < tempArray.count; i ++) {
            NSString *identify = tempArray[i];
            if ([identify isEqualToString:xtPeripheral.peripheral.identifier.UUIDString]) {
                [tempArray removeObject:identify];
            }
        }
        
        [def setObject:tempArray forKey:@"XTCBPeripheral.peripheral.save.key"];
        [def synchronize];
        
    }
    
}


/**
 获取已保存的蓝牙设备

 @return 蓝牙设备列表
 */
- (NSArray *)getSavedXTPeripherals {
    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
    NSArray *array = [def objectForKey:@"XTCBPeripheral.peripheral.save.key"];
    if (array.count > 0) {
        NSMutableArray *uuidArray = [[NSMutableArray alloc] init];
        for (int i = 0; i < array.count; i ++) {
            NSString *identify = array[i];
            [uuidArray addObject:[[NSUUID alloc] initWithUUIDString:identify]];
        }
        
        NSMutableArray *resultArray = [[NSMutableArray alloc] init];
        NSArray *periArr = [self.centralManager retrievePeripheralsWithIdentifiers:uuidArray];
        for (int i = 0; i < periArr.count; i ++) {
            XTCBPeripheral *deviceModel = [[XTCBPeripheral alloc] init];
            if ([deviceModel.peripheral.identifier.UUIDString isEqualToString:self.currentPeripheral.peripheral.identifier.UUIDString]) {
                deviceModel.connectState = self.currentPeripheral.connectState;
            } else {
                deviceModel.connectState = XTCBPeripheralNotConnected;
            }
            deviceModel.peripheral = periArr[i];
            [resultArray addObject:deviceModel];
        }
        return resultArray;
    }
    return nil;
}

/**
 睡眠

 @param time time
 */
- (void)sleepWithTime:(float)time {
    if (time > 0) {
        sleep(time);
    }
}

@end
