//
//  XTCBPeripheral.h
//  SuntrontBlueTooth
//
//  Created by apple on 2017/7/27.
//  Copyright © 2017年 apple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

extern NSString *const XTCBPeripheralConnectStateChangeKey;

typedef NS_ENUM(NSUInteger, XTCBPeripheralConnectState) {
    XTCBPeripheralNotConnected = 0,         //未连接
    XTCBPeripheralConnecting = 1,           //连接中
    XTCBPeripheralConnectingCanceled = 2,   //连接中被取消
    XTCBPeripheralConnectFailed = 3,        //连接失败
    XTCBPeripheralConnectTimeOut = 4,       //连接超时
    XTCBPeripheralConnectSuccess = 5,       //连接成功
    XTCBPeripheralDidDisconnect = 6,        //连接成功后断开连接
};

@interface XTCBPeripheral : NSObject

@property (nonatomic, strong) CBPeripheral *peripheral;
@property (nonatomic, assign) XTCBPeripheralConnectState connectState;
@property (nonatomic, strong) NSDictionary *advertisementData;
@property (nonatomic, strong) NSNumber *RSSI;
@property (nonatomic, strong) CBCharacteristic *writeCharacteristic;  //写特性
@property (nonatomic, strong) CBCharacteristic *nameCharacteristic;   //修改名字特性
@property (nonatomic, strong) CBCharacteristic *notifiyCharacteristic;//读特性

@end
