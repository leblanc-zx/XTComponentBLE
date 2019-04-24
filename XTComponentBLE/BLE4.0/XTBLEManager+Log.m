//
//  XTBLEManager+Log.m
//  XTComponentBLE
//
//  Created by apple on 2019/4/17.
//  Copyright © 2019年 新天科技股份有限公司. All rights reserved.
//

#import "XTBLEManager+Log.h"
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

NSString *const logPassword = @"3c3d0d30cf74973e1bc2b212f8cbae20";

typedef NS_ENUM(NSUInteger, XTBLELogType) { //日志类型
    XTBLELogTypeSendSetting,    //发送设置
    XTBLELogTypeSendData,       //发送数据
    XTBLELogTypeReceiveData,    //接收数据
    XTBLELogTypeSuccess,        //成功结果
    XTBLELogTypeFailure,        //失败结果
    XTBLELogTypeCutom           //自定义日志
};

void qhd_exchangeInstanceMethod(Class class, SEL originalSelector, SEL newSelector) {
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method newMethod = class_getInstanceMethod(class, newSelector);
    if(class_addMethod(class, originalSelector, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(class, newSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, newMethod);
    }
}

@implementation XTBLEManager (Log)
NSString *BLELogSign;

+ (void)load {
    qhd_exchangeInstanceMethod([self class], @selector(sendData:timeOut:timeInterval:startFilter:endFilter:success:failure:), @selector(qhd_sendData:timeOut:timeInterval:startFilter:endFilter:success:failure:));
    qhd_exchangeInstanceMethod([self class], @selector(peripheral:didUpdateValueForCharacteristic:error:), @selector(qhd_peripheral:didUpdateValueForCharacteristic:error:));
    
}

- (void)setMethodName:(NSString * _Nonnull)methodName  {
    objc_setAssociatedObject(self, @selector(methodName),methodName,OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSString *)methodName {
    return objc_getAssociatedObject(self, @selector(methodName));
}

- (void)setStartFileter:(NSString * _Nonnull)startFileter {
    objc_setAssociatedObject(self, @selector(startFileter),startFileter,OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSString *)startFileter {
    return objc_getAssociatedObject(self, @selector(startFileter));
}

- (void)setEndFilter:(NSString * _Nonnull)endFilter {
    objc_setAssociatedObject(self, @selector(endFilter),endFilter,OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSString *)endFilter {
    return objc_getAssociatedObject(self, @selector(endFilter));
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
- (void)qhd_sendData:(NSData *)data timeOut:(float)timeOut timeInterval:(float)timeInterval startFilter:(StartFilterData)startFilter endFilter:(EndFilterData)endFilter success:(ReceiveDataSuccessBlock)success failure:(ReceiveDataFailureBlock)failure {
    //log
    [self writeToFileWithObject:[NSString stringWithFormat:@"超时时间：%.3f秒    每帧间隔：%.3lf秒", timeOut, timeInterval] logType:XTBLELogTypeSendSetting];
    //log
    [self writeToFileWithObject:data logType:XTBLELogTypeSendData];
    
    [self qhd_sendData:data timeOut:timeOut timeInterval:timeInterval startFilter:startFilter endFilter:endFilter success:^(NSData *successData) {
        //log
        [self writeToFileWithObject:successData logType:XTBLELogTypeSuccess];
        if (success) {
            success(successData);
        }
    } failure:^(NSError *error) {
        //log
        [self writeToFileWithObject:[error.userInfo objectForKey:@"NSLocalizedDescription"] logType:XTBLELogTypeFailure];
        if (failure) {
            failure(error);
        }
    }];
}

// 读取新值的结果
- (void)qhd_peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    //log
    [self writeToFileWithObject:characteristic.value logType:XTBLELogTypeReceiveData];
    [self qhd_peripheral:peripheral didUpdateValueForCharacteristic:characteristic error:error];
}

/**
 打开记录日志功能
 
 @param password 密码
 */
- (void)registerLogWithPassword:(NSString *)password {
    if (password.length == 0) {
        return;
    }
    BLELogSign = [self MD5WithString:password];
}

/**
 获取MD5
 
 @param string 明文
 @return MD5字符串
 */
- (NSString *)MD5WithString:(NSString *)string
{
    const char *cStr = [string UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, strlen(cStr), digest );
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02X", digest[i]];
    
    return [output lowercaseString];
}

/**
 在请求方法中添加该函数
 
 @param method 方法名
 @param startFilter 开头过滤条件
 @param endFileter 结尾过滤条件
 */
- (void)log_method:(NSString *)method startFilter:(NSString *)startFilter endFilter:(NSString *)endFileter {
    self.methodName = method;
    self.startFileter = startFilter;
    self.endFilter = endFileter;
}

/**
 自定义日志

 @param custom 自定义日志字符串
 */
- (void)log_custom:(NSString *)custom {
    [self writeToFileWithObject:custom logType:XTBLELogTypeCutom];
}

/**
 获取当前时间
 
 @return yyyy-MM-dd HH:mm:ss
 */
- (NSString *)getCurrentTime {
    NSDate *date = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    return [dateFormatter stringFromDate:date];
}

/**
 写入txt文档
 
 @param object NSString || NSData
 @param logType 日志类型
 */
- (void)writeToFileWithObject:(id)object logType:(XTBLELogType)logType {
    
    if (![BLELogSign isEqualToString:logPassword]) {
        return;
    }
    
    NSMutableString *text = [[NSMutableString alloc] init];
    NSString *currentTime = [self getCurrentTime];
    switch (logType) {
        case XTBLELogTypeSendSetting:
        {
            [text appendFormat:@"\n\n@begin  method：%@\n", self.methodName.length > 0 ? self.methodName : @"未知"];
            [text appendFormat:@"\n<发送设置>%@</发送设置>\n", object];
            [text appendFormat:@"\n<开头过滤>%@</开头过滤>\n", self.startFileter.length > 0 ? self.startFileter : @"未知"];
            [text appendFormat:@"\n<结尾过滤>%@</结尾过滤>", self.endFilter.length > 0 ? self.endFilter : @"未知"];
        }
            break;
        case XTBLELogTypeSendData:
        {
            [text appendString:@"\n<发送>"];
            [text appendFormat:@"时间：%@", currentTime];
            [text appendFormat:@"    帧：%@", object];
            [text appendString:@"</发送>"];
        }
            break;
        case XTBLELogTypeReceiveData:
        {
            [text appendString:@"\n<接收>"];
            [text appendFormat:@"时间：%@", currentTime];
            [text appendFormat:@"    帧：%@", object];
            [text appendString:@"</接收>"];
        }
            break;
        case XTBLELogTypeSuccess:
        {
            [text appendString:@"\n<成功>"];
            [text appendFormat:@"时间：%@", currentTime];
            [text appendFormat:@"    帧：%@", object];
            [text appendString:@"</成功>"];
            [text appendString:@"\n\n@end\n\n"];
        }
            break;
        case XTBLELogTypeFailure:
        {
            [text appendString:@"\n<失败>"];
            [text appendFormat:@"时间：%@", currentTime];
            [text appendFormat:@"    Error：%@", object];
            [text appendString:@"</失败>"];
            [text appendString:@"\n\n@end\n\n"];
        }
            break;
        case XTBLELogTypeCutom:
        {
            [text appendFormat:@"\n\n@begin  method：custom\n"];
            [text appendFormat:@"\n%@", object];
            [text appendFormat:@"\n\n@end\n\n"];
        }
            break;
            
        default:
            break;
    }
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        @synchronized (self) {
            //获取沙盒路径
            NSArray *paths  = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES);
            //获取当前日期
            NSString *currentDay = [currentTime substringToIndex:10];
            //获取文件路径
            NSString *theFilePath = [[paths objectAtIndex:0] stringByAppendingFormat:@"/XTBLEDataLog%@.text", currentDay];
            //创建文件管理器
            NSFileManager *fileManager = [NSFileManager defaultManager];
            //如果文件不存在 创建文件
            if (![fileManager fileExistsAtPath:theFilePath]) {
                NSString *str = @"日志开始记录\n";
                [str writeToFile:theFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
            NSFileHandle *fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:theFilePath];
            [fileHandle seekToEndOfFile];  //将节点跳到文件的末尾
            NSData* stringData  = [[NSString stringWithFormat:@"%@\n",text] dataUsingEncoding:NSUTF8StringEncoding];
            [fileHandle writeData:stringData]; //追加写入数据
            [fileHandle closeFile];
        }
    });
}

/**
 获取日志列表
 
 @param months 月份 例：@[@"2019-02", @"2019-03", @"2019-04" ...]
 @return 日志列表
 */
- (NSArray *)getFileListWithMonths:(NSArray <NSString *>*)months {
    if (![BLELogSign isEqualToString:logPassword]) {
        return nil;
    }
    //获取沙盒路径
    NSString *doucumentPath  = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtPath:doucumentPath];
    
    NSMutableArray *resultList = [[NSMutableArray alloc] init];
    BOOL isDir = NO;
    for (NSString *path in directoryEnumerator.allObjects) {
        
        BOOL isExist = [fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", doucumentPath, path] isDirectory:&isDir];
        if (!isDir && isExist) {
            //NSLog(@"%@", path);// 文件路径
            for (NSString *month in months) {
                if ([path containsString:[NSString stringWithFormat:@"XTBLEDataLog%@", month]]) {
                    NSString *fileName = [path stringByReplacingOccurrencesOfString:@"XTBLEDataLog" withString:@""];
                    [resultList addObject:fileName];
                }
            }
        }
    }
    
    return resultList;
    
}

/**
 获取日志文件

 @param day 日期 yyyy-MM-dd
 @return 日志字符串
 */
- (NSString *)getFileWithDay:(NSString *)day {
    
    if (![BLELogSign isEqualToString:logPassword]) {
        return nil;
    }
    
    //获取沙盒路径
    NSArray *paths  = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES);
    //获取文件路径
    NSString *theFilePath = [[paths objectAtIndex:0] stringByAppendingFormat:@"/XTBLEDataLog%@.text", day];
    NSString *string = [[NSString alloc] initWithContentsOfFile:theFilePath encoding:NSUTF8StringEncoding error:nil];
    return string;
}

/**
 获取带颜色的日志文件

 @param day 日期 yyyy-MM-dd
 @return 日志字符串
 */
- (NSAttributedString *)getColorFileWithDay:(NSString *)day {
    NSString *fileStr = [self getFileWithDay:day];
    if (fileStr.length == 0) {
        fileStr = @"";
    }
    NSMutableAttributedString *colorStr = [[NSMutableAttributedString alloc] initWithString:fileStr];
    [colorStr addAttribute:NSForegroundColorAttributeName value:[UIColor redColor] range:NSMakeRange(0, fileStr.length)];
    NSScanner *scanner = [NSScanner scannerWithString:fileStr];
    NSString *text = nil;
    while ([scanner isAtEnd] == NO) {
        
        [scanner scanUpToString:@"@begin" intoString:nil];
        [scanner scanUpToString:@"@end" intoString:&text];
        
        NSString *subText = [NSString stringWithFormat:@"%@@end", text];
        NSRange range = [fileStr rangeOfString:subText];
        
        if ([subText containsString:@"<成功>"]) {
            [colorStr addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithRed:0.118 green:0.549 blue:0.337 alpha:1] range:range];
        }
        
    }
    return colorStr;
}

@end
