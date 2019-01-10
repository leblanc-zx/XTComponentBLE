//
//  XTCBPeripheral.h
//  SuntrontBlueTooth
//
//  Created by apple on 2017/7/27.
//  Copyright © 2017年 apple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

typedef NS_ENUM(NSUInteger, XTCBPeripheralConnectState) {
    XTCBPeripheralNotConnected = 0,     //未连接
    XTCBPeripheralConnecting = 1,       //连接中
    XTCBPeripheralConnectCanceled = 2,  //取消连接
    XTCBPeripheralConnectFailed = 3,    //连接失败
    XTCBPeripheralConnectTimeOut = 4,   //连接超时
    XTCBPeripheralConnectSuccess = 5,   //连接成功
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
