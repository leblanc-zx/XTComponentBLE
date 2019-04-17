//
//  XTBLEManager+Log.h
//  XTComponentBLE
//
//  Created by apple on 2019/4/17.
//  Copyright © 2019年 新天科技股份有限公司. All rights reserved.
//

#import "XTBLEManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface XTBLEManager (Log)

@property (nonatomic, strong, readonly) NSString *methodName;   //方法名
@property (nonatomic, strong, readonly) NSString *startFileter; //开头过滤条件
@property (nonatomic, strong, readonly) NSString *endFilter;    //结尾过滤条件

/**
 在请求方法中添加该函数

 @param method 方法名
 @param startFilter 开头过滤条件
 @param endFileter 结尾过滤条件
 */
- (void)log_method:(NSString *)method startFilter:(NSString *)startFilter endFilter:(NSString *)endFileter;

/**
 获取日志文件
 
 @param day 日期 yyyy-MM-dd
 @return 日志字符串
 */
- (NSString *)getFileWithDay:(NSString *)day;

@end

NS_ASSUME_NONNULL_END
