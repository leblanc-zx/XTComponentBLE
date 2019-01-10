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
NSString *const DIDDISCONNECT_BLOCK = @"DIDDISCONNECT_BLOCK";
NSString *const SEND_PROGRESSDATA_BLOCK = @"SEND_PROGRESSDATA_BLOCK";
NSString *const SEND_STARTFILTER_BLOCK = @"SEND_STARTFILTER_BLOCK";
NSString *const SEND_ENDFILTER_BLOCK = @"SEND_ENDFILTER_BLOCK";
NSString *const SEND_RECEIVEDATASUCCESS_BLOCK = @"SEND_RECEIVEDATASUCCESS_BLOCK";
NSString *const SEND_RECEIVEDATAFAILURE_BLOCK = @"SEND_RECEIVEDATAFAILURE_BLOCK";
NSString *const CENTRALMANAGER_DIDUPDATESTATE_BLOCK = @"CENTRALMANAGER_DIDUPDATESTATE_BLOCK";

@interface XTBLEManager ()<CBCentralManagerDelegate, CBPeripheralDelegate>

/*----BlockDic----*/
@property (nonatomic, strong) NSMutableDictionary *blockDictionary;

/*----Timer----*/
@property (nonatomic, strong) NSMutableDictionary *timerDictionary;

/*----Scan----*/
@property (nonatomic, strong) NSMutableArray *BLEDevices;
@property (nonatomic, assign) BOOL isScanning;        //正在扫描

/*----connect----*/
@property (nonatomic, strong) XTCBPeripheral *currentPeripheral;         //当前的蓝牙设备
//@property (nonatomic, strong) CBCharacteristic *writeCharacteristic;     //当前的写特性
//@property (nonatomic, strong) CBCharacteristic *changeNameCharacteristic;//当前修改名字特性
//@property (nonatomic, strong) CBCharacteristic *notifiyCharacteristic;   //当前的通知特性

/*----发送数据----*/
@property (nonatomic, strong) NSMutableData *responseData;

@property (nonatomic, assign) BOOL isBLEEnable;       //蓝牙是否可用


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
 *  创建蓝牙管理
 */
- (void)createBLEManager {
    
    // 1.创建管理中心
    self.centralManager = [[CBCentralManager alloc]initWithDelegate:self queue:dispatch_get_main_queue() options:nil];
    
}

/**
 扫描蓝牙

 @param time 扫描时间 默认15秒
 @param scanBlock 返回扫描到的设备列表
 @param finishBlock 扫描结束
 */
- (void)scanWithTime:(int)time scanBlock:(ScanBlock)scanBlock finishBlock:(ScanFinishBlock)finishBlock {
    if (!self.isBLEEnable) {
        if (finishBlock) {
            finishBlock([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeBLENotEnable userInfo:@{@"NSLocalizedDescription":@"请打开蓝牙"}]);
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
    int scanTime = time > 0 ? time : 15;
    [self.BLEDevices removeAllObjects];
    
    //开始扫描
    self.isScanning = YES;
    [self.centralManager scanForPeripheralsWithServices:nil options:nil];
    
    //开启定时器
    __weak typeof(self) weakSelf = self;
    [self openTimerWithIdentity:TIMER_SCAN timeDuration:scanTime block:^(TimerState state, NSError *error) {
        
        ScanFinishBlock cahcheFinishBlock = [self.blockDictionary objectForKey:SCAN_FINISHBLOCK];
        [self.blockDictionary removeObjectForKey:SCAN_BLOCK];
        
        if (state == TimerStateFinish) {
            //timer时间到了,扫描结束
            weakSelf.isScanning = NO;
            [weakSelf.centralManager stopScan];
            if (cahcheFinishBlock) {
                [self.blockDictionary removeObjectForKey:SCAN_FINISHBLOCK];
                cahcheFinishBlock(nil);
            }
        } else if (state == TimerStateCancel) {
            //timer被取消
            //扫描被取消了
            self.isScanning = NO;
            [self.centralManager stopScan];
            if (cahcheFinishBlock) {
                [self.blockDictionary removeObjectForKey:SCAN_FINISHBLOCK];
                cahcheFinishBlock(error);
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
- (void)connectWithPeripheral:(XTCBPeripheral *)peripheral timeOut:(int)timeOut success:(ConnectSuccessBlock)success failure:(ConnectFailureBlock)failure {
    
    if (!self.isBLEEnable) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeBLENotEnable userInfo:@{@"NSLocalizedDescription":@"请打开蓝牙"}]);
        }
        return;
    }
    
    //正在连接
    if (self.currentPeripheral && self.currentPeripheral.connectState == XTCBPeripheralConnecting) {
        if (failure) {
            NSString *msg = [NSString stringWithFormat:@"正在连接%@,请稍后再试",self.currentPeripheral.peripheral.name];
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectFailed userInfo:@{@"NSLocalizedDescription":msg}]);
        }
        return;
    }
    
    if (!peripheral) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeNotDevice userInfo:@{@"NSLocalizedDescription":@"请选择要连接的蓝牙设备"}]);
        }
        return;
    }
    
    if ([peripheral.peripheral.identifier.UUIDString isEqualToString:self.currentPeripheral.peripheral.identifier.UUIDString] && self.currentPeripheral.connectState == XTCBPeripheralConnectSuccess) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectFailed userInfo:@{@"NSLocalizedDescription":@"已连接该蓝牙设备"}]);
        }
        return;
    }
    
    //预备连接
    int connectTimeOut = timeOut > 0 ? timeOut : 15;
    XTCBPeripheral *lastPeripheral = self.currentPeripheral;
    if (success) {
        [self.blockDictionary setObject:success forKey:CONNECT_SUCCESSBLOCK];
    }
    if (failure) {
        [self.blockDictionary setObject:failure forKey:CONNECT_FAILUREBLOCK];
    }
    _currentPeripheral = peripheral;
    _currentPeripheral.connectState = XTCBPeripheralConnecting;
    
    //自动断开上个连接
    if (lastPeripheral) {
        [self.centralManager cancelPeripheralConnection:lastPeripheral.peripheral];
        lastPeripheral.connectState = XTCBPeripheralNotConnected;
    }
    
    //开始连接
    [self.centralManager connectPeripheral:self.currentPeripheral.peripheral options:@{CBConnectPeripheralOptionNotifyOnConnectionKey:@YES,CBConnectPeripheralOptionNotifyOnDisconnectionKey:@YES,CBConnectPeripheralOptionNotifyOnNotificationKey:@YES}];
    peripheral.peripheral.delegate = self;
    
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
                cacheFailureBlock([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectTimeOut userInfo:@{@"NSLocalizedDescription":@"连接超时"}]);
            }
            
        } else if (state == TimerStateCancel) {
            //timer被取消
            if (weakSelf.currentPeripheral.connectState == XTCBPeripheralConnectFailed) {
                //连接失败
                [weakSelf.centralManager cancelPeripheralConnection:weakSelf.currentPeripheral.peripheral];
                [self.blockDictionary removeObjectForKey:CONNECT_SUCCESSBLOCK];
                ConnectFailureBlock cacheFailureBlock = [self.blockDictionary objectForKey:CONNECT_FAILUREBLOCK];
                if (cacheFailureBlock) {
                    [self.blockDictionary removeObjectForKey:CONNECT_FAILUREBLOCK];
                    cacheFailureBlock(error);
                }
            } else if (weakSelf.currentPeripheral.connectState == XTCBPeripheralConnectCanceled) {
                //连接被取消
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
            } else if (weakSelf.currentPeripheral.connectState == XTCBPeripheralConnecting) {
                //连接中
                [weakSelf.centralManager cancelPeripheralConnection:weakSelf.currentPeripheral.peripheral];
                [self.blockDictionary removeObjectForKey:CONNECT_SUCCESSBLOCK];
                ConnectFailureBlock cacheFailureBlock = [self.blockDictionary objectForKey:CONNECT_FAILUREBLOCK];
                if (cacheFailureBlock) {
                    [self.blockDictionary removeObjectForKey:CONNECT_FAILUREBLOCK];
                    cacheFailureBlock([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectFailed userInfo:@{@"NSLocalizedDescription": @"代码异常"}]);
                }
            } else if (weakSelf.currentPeripheral.connectState == XTCBPeripheralNotConnected) {
                //未连接
                [weakSelf.centralManager cancelPeripheralConnection:weakSelf.currentPeripheral.peripheral];
                [self.blockDictionary removeObjectForKey:CONNECT_SUCCESSBLOCK];
                ConnectFailureBlock cacheFailureBlock = [self.blockDictionary objectForKey:CONNECT_FAILUREBLOCK];
                if (cacheFailureBlock) {
                    [self.blockDictionary removeObjectForKey:CONNECT_FAILUREBLOCK];
                    cacheFailureBlock([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectFailed userInfo:@{@"NSLocalizedDescription": @"代码异常"}]);
                }
            }
        }
    }];
    
}

/**
 重新连接蓝牙设备
 
 @param bleDeviceInfo 蓝牙设备信息
 @param timeOut 超时时间 默认15秒
 @param success 成功
 @param failure 失败
 */
- (void)reConnectWithTimeOut:(int)timeOut success:(ConnectSuccessBlock)success failure:(ConnectFailureBlock)failure {
    [self connectWithPeripheral:self.currentPeripheral timeOut:timeOut success:success failure:failure];
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
    [self sendData:data timeOut:10 startFilter:startFilter endFilter:endFilter success:success failure:failure];
}

/**
 发送数据
 
 @param data 帧数据
 @param timeOut 超时时间
 @param startFilter 开始条件
 @param endFilter 结束条件
 @param success 处理并拼接后的帧数据
 @param failure 出错
 */
- (void)sendData:(NSData *)data timeOut:(int)timeOut startFilter:(StartFilterData)startFilter endFilter:(EndFilterData)endFilter success:(ReceiveDataSuccessBlock)success failure:(ReceiveDataFailureBlock)failure {
    [self sendData:data characteristic:self.currentPeripheral.writeCharacteristic timeOut:timeOut startFilter:startFilter endFilter:endFilter success:success failure:failure];
}

/**
 发送数据

 @param data 帧数据
 @param timeOut 超时时间
 @param startFilter 开始条件
 @param endFilter 结束条件
 @param success 处理并拼接后的帧数据
 @param failure 出错
 */
- (void)sendData:(NSData *)data characteristic:(CBCharacteristic *)characteristic timeOut:(int)timeOut startFilter:(StartFilterData)startFilter endFilter:(EndFilterData)endFilter success:(ReceiveDataSuccessBlock)success failure:(ReceiveDataFailureBlock)failure {
    
    if (!self.isBLEEnable) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeBLENotEnable userInfo:@{@"NSLocalizedDescription":@"请打开蓝牙"}]);
        }
        return;
    }
    
    if (self.currentPeripheral.peripheral.state != CBPeripheralStateConnected) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeNotConnect userInfo:@{@"NSLocalizedDescription": @"请先连接蓝牙"}]);
        }
        return;
    }
    if (self.currentPeripheral.connectState != XTCBPeripheralConnectSuccess) {
        if (failure) {
            failure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeSendFailed userInfo:@{@"NSLocalizedDescription": @"没有发现写特性"}]);
        }
        return;
    }
    
    //预备发送数据
    self.responseData = [[NSMutableData alloc] init];
    
    if (startFilter) {
        [self.blockDictionary setObject:startFilter forKey:SEND_STARTFILTER_BLOCK];
    }
    if (endFilter) {
        [self.blockDictionary setObject:endFilter forKey:SEND_ENDFILTER_BLOCK];
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
            }
            NSData *leftData = [data subdataWithRange:NSMakeRange(index, data.length - index)];
            if (leftData) {
                [self.currentPeripheral.peripheral writeValue:leftData forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
            }
            
        } else {
            [self.currentPeripheral.peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
        }
        
    } else {
        error = [NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeSendFailed userInfo:@{@"NSLocalizedDescription": @"特性不可写"}];
    }
    
    if (error) {
        [self.blockDictionary removeObjectForKey:SEND_STARTFILTER_BLOCK];
        [self.blockDictionary removeObjectForKey:SEND_ENDFILTER_BLOCK];
        [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATASUCCESS_BLOCK];
        ReceiveDataFailureBlock cacheReceiveDataFailure = [self.blockDictionary objectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
        if (cacheReceiveDataFailure) {
            [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
            cacheReceiveDataFailure(error);
        }
        return;
    }
    
    int duration = timeOut > 0 ? timeOut : 10;
    [self openTimerWithIdentity:TIMER_RECEIVE_DATA timeDuration:duration block:^(TimerState state, NSError *error) {
        
        if (state == TimerStateFinish) {
            //timer正常结束，超时了
            [self.blockDictionary removeObjectForKey:SEND_STARTFILTER_BLOCK];
            [self.blockDictionary removeObjectForKey:SEND_ENDFILTER_BLOCK];
            [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATASUCCESS_BLOCK];
            ReceiveDataFailureBlock cacheReceiveDataFailure = [self.blockDictionary objectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
            if (cacheReceiveDataFailure) {
                [self.blockDictionary removeObjectForKey:SEND_RECEIVEDATAFAILURE_BLOCK];
                cacheReceiveDataFailure([NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeReceiveTimeOut userInfo:@{@"NSLocalizedDescription": @"请求超时"}]);
            }
        }
        if (state == TimerStateCancel) {
            //timer被取消了
            if (error) {
                //数据接收异常 || 数据接收被取消
                [self.blockDictionary removeObjectForKey:SEND_STARTFILTER_BLOCK];
                [self.blockDictionary removeObjectForKey:SEND_ENDFILTER_BLOCK];
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
    [self cancelTimerWithIdentity:TIMER_SCAN error:[NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeScanCanceled userInfo:@{@"NSLocalizedDescription": @"扫描被取消"}]];
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
    
    if (self.currentPeripheral.connectState == XTCBPeripheralNotConnected || self.currentPeripheral.connectState == XTCBPeripheralConnectFailed || self.currentPeripheral.connectState == XTCBPeripheralConnectTimeOut || self.currentPeripheral.connectState == XTCBPeripheralConnectCanceled || self.currentPeripheral.connectState == XTCBPeripheralConnectSuccess) {
        //未连接、连接失败、连接超时、已被取消过了、已连接成功了，不做处理
        return;
    }
    if (self.currentPeripheral.connectState == XTCBPeripheralConnecting) {
        //连接中
        self.currentPeripheral.connectState = XTCBPeripheralConnectCanceled;
        [self cancelTimerWithIdentity:TIMER_CONNECT error:[NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeConnectCanceled userInfo:@{@"NSLocalizedDescription": @"连接被取消"}]];
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
    [self cancelTimerWithIdentity:TIMER_RECEIVE_DATA error:[NSError errorWithDomain:@"错误" code:XTBLENSErrorCodeReceiveCanceled userInfo:@{@"NSLocalizedDescription": @"请求被取消"}]];
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
 蓝牙连接状态（断开连接）监听
 
 @param didDisConnectBlock 回调
 */
- (void)setBlockOnDidDisConnect:(DidDisConnectBlock)didDisConnectBlock {
    [self.blockDictionary setObject:didDisConnectBlock forKey:DIDDISCONNECT_BLOCK];
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
- (void)changeDeviceName:(NSString *)deviceName success:(void (^)())success failure:(void (^)(NSError *))failure {
    NSData *requestData = [deviceName dataUsingEncoding:NSUTF8StringEncoding];
    [self sendData:requestData characteristic:self.currentPeripheral.nameCharacteristic timeOut:10 startFilter:nil endFilter:nil success:^(NSData *data) {
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
- (void)openTimerWithIdentity:(NSString *)identity timeDuration:(int)duration block:(TimerBlock)block {
    
    if (identity.length == 0) {
        return;
    }
    
    //创建线程队列
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    //移除上次任务
    dispatch_source_t timer = [self.timerDictionary objectForKey:identity];
    if (timer) {
        [self cancelTimerWithIdentity:identity error:nil];
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
        if (self.currentPeripheral.connectState == XTCBPeripheralConnectTimeOut || self.currentPeripheral.connectState == XTCBPeripheralConnectFailed || self.currentPeripheral.connectState == XTCBPeripheralNotConnected || self.currentPeripheral.connectState == XTCBPeripheralConnecting || self.currentPeripheral.connectState == XTCBPeripheralConnectCanceled) {
            //连接超时、连接失败、未连接、连接中，不需要处理
            return;
        }
        //连接成功的断开才需要通知
        self.currentPeripheral.connectState = XTCBPeripheralConnectCanceled;
        DidDisConnectBlock chacheDidDisConnectBlock = [self.blockDictionary objectForKey:DIDDISCONNECT_BLOCK];
        if (chacheDidDisConnectBlock) {
            if (error.code == CBErrorPeripheralDisconnected) {
                chacheDidDisConnectBlock(peripheral, [NSError errorWithDomain:error.domain code:error.code userInfo:@{@"NSLocalizedDescription": @"断开连接"}]);
            } else {
                chacheDidDisConnectBlock(peripheral, error);
            }
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
    
    //开始拼接条件
    StartFilterData startFilterDataBlock = [self.blockDictionary objectForKey:SEND_STARTFILTER_BLOCK];
    if (startFilterDataBlock) {
        //设置了条件
        BOOL canStartJoint = startFilterDataBlock(characteristic.value);
        if (!canStartJoint) {
            //还不能开始，就一直等待
            return;
        }
    }
    
    //可以开始拼接了：未设置开始条件 || 条件已通过
    [self.blockDictionary removeObjectForKey:SEND_STARTFILTER_BLOCK];//开始条件已经不需要了
    
    //拼接数据
    [self.responseData appendData:characteristic.value];
    
    //结束拼接条件
    EndFilterData endFilterDataBlock = [self.blockDictionary objectForKey:SEND_ENDFILTER_BLOCK];
    if (endFilterDataBlock) {
        //设置了条件
        BOOL canEndJoint = endFilterDataBlock(self.responseData);
        if (!canEndJoint) {
            //还不能结束，就一直等待
            return;
        }
    }
    
    //可以结束了
    if (endFilterDataBlock) {
        //设置了条件，并且已经通过了
        [self.blockDictionary removeObjectForKey:SEND_ENDFILTER_BLOCK];//结束条件已经不需要了
        [self receiveDataFinish:nil];
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

@end
