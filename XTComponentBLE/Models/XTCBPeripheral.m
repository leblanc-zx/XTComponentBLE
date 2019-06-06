//
//  XTCBPeripheral.m
//  SuntrontBlueTooth
//
//  Created by apple on 2017/7/27.
//  Copyright © 2017年 apple. All rights reserved.
//

#import "XTCBPeripheral.h"

NSString *const XTCBPeripheralConnectStateChangeKey = @"XTCBPeripheralConnectStateChangeKey";

@implementation XTCBPeripheral

- (void)setConnectState:(XTCBPeripheralConnectState)connectState {
    _connectState = connectState;
    [[NSNotificationCenter defaultCenter] postNotificationName:XTCBPeripheralConnectStateChangeKey object:self];
}

@end
