//
//  XTBLEManager.h
//  SuntrontBlueTooth
//
//  Created by apple on 2017/7/28.
//  Copyright © 2017年 apple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XTCBPeripheral.h"
#import <CoreBluetooth/CoreBluetooth.h>

#define WRITE_CHARACTERISTICS @"FF01"
#define NOTIFIY_CHARACTERISTICS @"FF02"
#define CHANGENAME_CHARACTERISTICS @"FF06"
#define LimitLength 20 //20个字节分段发送

typedef NS_ENUM(NSUInteger, XTBLENSErrorCode) {
    XTBLENSErrorCodeBLENotEnable = 1000,    //蓝牙不可用
    XTBLENSErrorCodeScanCanceled = 1001,    //扫描被取消
    XTBLENSErrorCodeNotDevice = 1003,       //未选择设备
    XTBLENSErrorCodeConnectFailed = 1004,   //连接失败
    XTBLENSErrorCodeConnectTimeOut = 1005,  //连接超时
    XTBLENSErrorCodeConnectCanceled = 1006, //连接被取消
    XTBLENSErrorCodeNotConnect= 1007,       //未连接设备
    XTBLENSErrorCodeSendFailed = 1008,      //发送失败
    XTBLENSErrorCodeReceiveFailed = 1009,   //接收失败
    XTBLENSErrorCodeReceiveTimeOut = 1010,  //接收超时
    XTBLENSErrorCodeReceiveCanceled = 1011, //接收被取消
};

typedef void(^ScanBlock)(NSArray *bleDevices);
typedef void(^ScanFinishBlock)(NSError *error);
typedef void(^ConnectSuccessBlock)(void);
typedef void(^ConnectFailureBlock)(NSError *error);
typedef void(^DidDisConnectBlock)(CBPeripheral *peripheral, NSError *error);
typedef BOOL(^StartFilterData)(NSData *receiveData);
typedef BOOL(^EndFilterData)(NSData *JointData);
typedef void(^ReceiveDataSuccessBlock)(NSData *data);
typedef void(^ReceiveDataFailureBlock)(NSError *error);
typedef void(^CentralManagerDidUpdateState)(CBCentralManager *central);

@interface XTBLEManager : NSObject

@property (nonatomic, strong) CBCentralManager *centralManager; //蓝牙管理
@property (nonatomic, assign, readonly) BOOL isScanning;        //正在扫描
@property (nonatomic, assign, readonly) BOOL isBLEEnable;       //蓝牙是否可用
@property (nonatomic, assign, readonly) BOOL isRequesting;      //蓝牙是否正在请求数据
@property (nonatomic, strong, readonly) XTCBPeripheral *currentPeripheral;      //当前的蓝牙设备

/**
 *  创建蓝牙管理
 */
+ (id)sharedManager;

/**
 扫描蓝牙
 
 @param time 扫描时间 默认15秒
 @param scanBlock 返回扫描到的设备列表
 @param finishBlock 扫描结束
 */
- (void)scanWithTime:(int)time scanBlock:(ScanBlock)scanBlock finishBlock:(ScanFinishBlock)finishBlock;

/**
 连接蓝牙设备
 
 @param peripheral 蓝牙设备
 @param timeOut 超时时间 默认15秒
 @param success 成功
 @param failure 失败
 */
- (void)connectWithPeripheral:(XTCBPeripheral *)peripheral timeOut:(int)timeOut success:(ConnectSuccessBlock)success failure:(ConnectFailureBlock)failure;

/**
 重新连接蓝牙设备
 
 @param timeOut 超时时间 默认15秒
 @param success 成功
 @param failure 失败
 */
- (void)reConnectWithTimeOut:(int)timeOut success:(ConnectSuccessBlock)success failure:(ConnectFailureBlock)failure;

/**
 发送数据
 
 @param data 帧数据
 @param startFilter 开始条件
 @param endFilter 结束条件
 @param success 处理并拼接后的帧数据
 @param failure 出错
 */
- (void)sendData:(NSData *)data startFilter:(StartFilterData)startFilter endFilter:(EndFilterData)endFilter success:(ReceiveDataSuccessBlock)success failure:(ReceiveDataFailureBlock)failure;

/**
 发送数据
 
 @param data 帧数据
 @param timeOut 超时时间
 @param startFilter 开始条件
 @param endFilter 结束条件
 @param success 处理并拼接后的帧数据
 @param failure 出错
 */
- (void)sendData:(NSData *)data timeOut:(int)timeOut startFilter:(StartFilterData)startFilter endFilter:(EndFilterData)endFilter success:(ReceiveDataSuccessBlock)success failure:(ReceiveDataFailureBlock)failure;

/**
 取消扫描蓝牙设备
 */
- (void)cancelScan;

/**
 取消蓝牙连接
 */
- (void)cancelConnect;

/**
 取消接收数据
 */
- (void)cancelReceiveData;

/**
 关闭Manager
 */
- (void)doClose;

/**
 蓝牙连接状态（断开连接）监听
 
 @param didDisConnectBlock 回调
 */
- (void)setBlockOnDidDisConnect:(DidDisConnectBlock)didDisConnectBlock;


/**
 设备状态改变的委托

 @param block 状态改变 回调
 */
- (void)setBlockOnCentralManagerDidUpdateState:(CentralManagerDidUpdateState)block;

/**
 修改设备名称
 
 @param deviceName 新设备名
 @param success success
 @param failure error
 */
- (void)changeDeviceName:(NSString *)deviceName success:(void(^)())success failure:(void(^)(NSError *error))failure;

/**
 保存蓝牙设备
 
 @param xtPeripheral 蓝牙设备
 */
- (void)saveXTPeripheral:(XTCBPeripheral *)xtPeripheral;

/**
 移除已保存的蓝牙设备
 
 @param xtPeripheral 蓝牙设备
 */
- (void)removeSavedXTPeripheral:(XTCBPeripheral *)xtPeripheral;

/**
 获取已保存的蓝牙设备
 
 @return 蓝牙设备列表
 */
- (NSArray *)getSavedXTPeripherals;

@end
