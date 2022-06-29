//
//  QGFileDownloader.m
//  QGFileDownloader
//
//  Created by QG on 2022/06/29.
//  Forked from AFImageDownloader and modified by QG.
//

#import "QGFileDownloader.h"
#import <AFNetworking/AFHTTPSessionManager.h>

/// 判断对象是否为空
#define QGIsEmpty(obj) (obj == nil || [obj isEqual:NSNull.null] || [obj isEqual:@""])
/// 判断对象是否不为空
#define QGIsNotEmpty(obj) (!QGIsEmpty(obj))
/// Weakify & Strongify
#define QGWeakify(object) __weak __typeof__(object) weak##_##object = object;
#define QGStrongify(object) __typeof__(object) object = weak##_##object;

NS_ASSUME_NONNULL_BEGIN

NSString * const QGFileDownloaderDomain = @"com.cqmh.QGFileDownloader";

#pragma mark - QGFileDownloadReceipt

@interface QGFileDownloadReceipt ()

@property (nonatomic, strong) NSUUID *receiptID;
@property (nonatomic, strong) NSString *URLString;

@end

@implementation QGFileDownloadReceipt

- (instancetype)initWithReceiptID:(NSUUID *)receiptID URLString:(NSString *)URLString {
    if (self = [self init]) {
        _receiptID = receiptID;
        _URLString = URLString;
    }
    return self;
}

@end

#pragma mark - QGFileDownloaderResponseHandler

@interface QGFileDownloaderResponseHandler ()

@property (nonatomic, strong) NSUUID *handlerID;

@property (nonatomic, strong) NSString *destinationPath;

@property (nonatomic, copy, nullable) QGFileDownloadProgressBlock progressBlock;

@property (nonatomic, copy, nullable) QGFileDownloadCompletionBlock completionBlock;

@end

@implementation QGFileDownloaderResponseHandler

- (instancetype)initWithHandlerID:(NSUUID *)handlerID
                  destinationPath:(NSString *)destinationPath
                    progressBlock:(QGFileDownloadProgressBlock _Nullable)progressBlock
                  completionBlock:(QGFileDownloadCompletionBlock _Nullable)completionBlock {
    if (self = [self init]) {
        _handlerID = handlerID;
        _destinationPath = destinationPath;
        _progressBlock = progressBlock;
        _completionBlock = completionBlock;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat: @"<QGFileDownloaderResponseHandler>UUID: %@", [self.handlerID UUIDString]];
}

@end

#pragma mark - QGFileDownloaderMergedTask

@interface QGFileDownloaderMergedTask ()

@property (nonatomic, strong) NSUUID *taskID;

@property (nonatomic, strong) NSString *URLIdentifier;

@property (nonatomic, strong) NSURLSessionDownloadTask *task;

@property (nonatomic, strong) NSMutableArray<QGFileDownloaderResponseHandler *> *responseHandlers;

@property (nonatomic, strong) dispatch_semaphore_t lock;

@end

@implementation QGFileDownloaderMergedTask

- (instancetype)initWithURLIdentifier:(NSString *)URLIdentifier taskID:(NSUUID *)taskID task:(NSURLSessionDownloadTask *)task {
    if (self = [self init]) {
        _URLIdentifier = URLIdentifier;
        _task = task;
        _taskID = taskID;
        _lock = dispatch_semaphore_create(1);
        _responseHandlers = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)addResponseHandler:(QGFileDownloaderResponseHandler *)handler {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    [self.responseHandlers addObject:handler];
    dispatch_semaphore_signal(_lock);
}

- (void)removeResponseHandler:(QGFileDownloaderResponseHandler *)handler {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    [self.responseHandlers removeObject:handler];
    dispatch_semaphore_signal(_lock);
}

- (NSArray<QGFileDownloaderResponseHandler *> *)getResponseHandlers {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    NSArray *responseHandlers = [NSArray arrayWithArray:_responseHandlers];
    dispatch_semaphore_signal(_lock);
    
    return responseHandlers;
}

- (QGFileDownloaderResponseHandler *_Nullable)responseHandlerWithHandlerID:(NSUUID *)handlerID {
    QGFileDownloaderResponseHandler *theHandler = nil;
    
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    for (QGFileDownloaderResponseHandler *handler in _responseHandlers) {
        if ([handler.handlerID isEqual:handlerID]) {
            theHandler = handler;
            break;
        }
    }
    dispatch_semaphore_signal(_lock);
    
    return theHandler;
}

@end

#pragma mark - QGFileDownloader

@interface QGFileDownloader ()

@property (nonatomic, strong) dispatch_queue_t synchronizationQueue;
@property (nonatomic, strong) dispatch_queue_t responseQueue;

@property (nonatomic, assign) NSInteger maximumActiveDownloads;
@property (nonatomic, assign) NSInteger activeRequestCount;

@property (nonatomic, strong) NSMutableArray *queuedMergedTasks;
@property (nonatomic, strong) NSMutableDictionary *mergedTasks;

@property (nonatomic, strong) AFHTTPSessionManager *sessionManager;

@end

@implementation QGFileDownloader

#pragma mark - Init

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _sessionManager = [self.class defaultHTTPSessionManager];
        _maximumActiveDownloads = 4;
        
        _queuedMergedTasks = [NSMutableArray array];
        _mergedTasks = [NSMutableDictionary dictionary];
        _activeRequestCount = 0;
        
        NSString *name = [NSString stringWithFormat:@"%@.synchronizationqueue-%@", QGFileDownloaderDomain, NSUUID.UUID.UUIDString];
        _synchronizationQueue = dispatch_queue_create([name cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_SERIAL);
        
        name = [NSString stringWithFormat:@"%@.responsequeue-%@", QGFileDownloaderDomain, NSUUID.UUID.UUIDString];
        _responseQueue = dispatch_queue_create([name cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

#pragma mark - 默认配置

+ (NSURLCache *)defaultURLCache {
    
    // It's been discovered that a crash will occur on certain versions
    // of iOS if you customize the cache.
    //
    // More info can be found here: https://devforums.apple.com/message/1102182#1102182
    //
    // When iOS 7 support is dropped, this should be modified to use
    // NSProcessInfo methods instead.
    if ([[[UIDevice currentDevice] systemVersion] compare:@"8.2" options:NSNumericSearch] == NSOrderedAscending) {
        return [NSURLCache sharedURLCache];
    }
    
    static NSURLCache *URLCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        URLCache = [[NSURLCache alloc] initWithMemoryCapacity:20 * 1024 * 1024
                                                 diskCapacity:150 * 1024 * 1024
                                                     diskPath:QGFileDownloaderDomain];
    });
    
    return URLCache;
}

+ (NSURLSessionConfiguration *)defaultURLSessionConfiguration {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    configuration.HTTPShouldSetCookies = YES;
    configuration.HTTPShouldUsePipelining = NO;
    
    configuration.requestCachePolicy = NSURLRequestUseProtocolCachePolicy;
    configuration.allowsCellularAccess = YES;
    configuration.timeoutIntervalForRequest = 60.0;
    configuration.URLCache = [self defaultURLCache];
    
    return configuration;
}

+ (AFHTTPSessionManager *)defaultHTTPSessionManager {
    AFHTTPSessionManager *sharedManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:[self defaultURLSessionConfiguration]];
    
    sharedManager.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"application/json", @"text/html", @"text/plain", nil];
    [sharedManager.requestSerializer setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [sharedManager.requestSerializer setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [sharedManager.requestSerializer setTimeoutInterval:30.0f];
    
    return sharedManager;
}

#pragma mark - 单例

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static QGFileDownloader *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

#pragma mark - 下载文件

- (QGFileDownloadReceipt *_Nullable)downloadFile:(nullable NSString *)URLString
                                        destPath:(NSString *)destPath
                                      completion:(QGFileDownloadCompletionBlock _Nullable)completion
{
    return [self downloadFile:URLString destPath:destPath progress:nil completion:completion];
}

- (QGFileDownloadReceipt *_Nullable)downloadFile:(NSString *)URLString
                                        destPath:(NSString *)destPath
                                        progress:(QGFileDownloadProgressBlock _Nullable)progress
                                      completion:(QGFileDownloadCompletionBlock _Nullable)completion
{
    return [self downloadFile:URLString destPath:destPath removeCachedResponse:NO progress:progress completion:completion];
}

- (QGFileDownloadReceipt *_Nullable)downloadFile:(NSString *)URLString
                                        destPath:(NSString *)destPath
                            removeCachedResponse:(BOOL)removeCachedResponse
                                        progress:(QGFileDownloadProgressBlock _Nullable)progress
                                      completion:(QGFileDownloadCompletionBlock _Nullable)completion {
    return [self downloadFile:URLString
                     destPath:destPath
                      headers:nil
         removeCachedResponse:removeCachedResponse
                     progress:progress
                   completion:completion];
}

- (QGFileDownloadReceipt *_Nullable)downloadFile:(NSString *)URLString
                                        destPath:(NSString *)destPath
                                         headers:(nullable NSDictionary<NSString *,NSString *> *)headers
                            removeCachedResponse:(BOOL)removeCachedResponse
                                        progress:(QGFileDownloadProgressBlock _Nullable)progress
                                      completion:(QGFileDownloadCompletionBlock _Nullable)completion
{
    // 检查传入的下载地址和目标存放路径是否合法
    NSError *error = [self checkDownloadURLString:URLString destinationPath:destPath];
    if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(error);
            }
        });
        return nil;
    }

    NSUUID *handlerID = [NSUUID UUID];
    __block NSURLSessionDownloadTask *task = nil;
    
    dispatch_sync(_synchronizationQueue, ^{
        // 是否有需要合并的下载任务
        QGFileDownloaderMergedTask *existingTask = self.mergedTasks[URLString];
        if (existingTask != nil) {
            QGFileDownloaderResponseHandler *responseHandler = [[QGFileDownloaderResponseHandler alloc] initWithHandlerID:handlerID
                                                                                                          destinationPath:destPath
                                                                                                            progressBlock:progress
                                                                                                          completionBlock:completion];
            [existingTask addResponseHandler:responseHandler];
            task = existingTask.task;
            return;// 退出 block
        }
        
        // 检查目标位置是否有文件
        if ([NSFileManager.defaultManager fileExistsAtPath:destPath]) {
            
            // 如果目标路劲下已有对应文件, 则认为已下载, 视为缓存在目标位置的下载文件.
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil);
                }
            });
            return;// 退出 block
        }
        
        // 检查是否有缓存
        if ([self hasCachedFileWithURLString:URLString]) {
            // 否则, 查看下载器特定的缓存
            if ([self linkCachedFileWithURLString:URLString toTargetPath:destPath]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(nil);
                    }
                });
                return;// 退出 block
            } else {
                // 创建hard link失败, 不应该出现的情况
                NSAssert(NO, @"创建hard link失败!");
                // 移除缓存, 重新下载
                [self removeCachedFileWithURLString:URLString];
            }
        }
        
        // 创建下载任务
        __block QGFileDownloaderMergedTask *mergedTask = nil;
        
        QGWeakify(self);
        // 进度回调
        QGFileDownloadProgressBlock progressBlock = ^(NSProgress * _Nonnull downloadProgress) {
            if (mergedTask != nil) {
                NSArray<QGFileDownloaderResponseHandler *> *responseHandlers = [mergedTask getResponseHandlers];
                for (QGFileDownloaderResponseHandler *responseHandler in responseHandlers) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (responseHandler.progressBlock) {
                            responseHandler.progressBlock(downloadProgress);
                        }
                    });
                }
            } else {
                NSAssert(NO, @"下载任务异常!");
            }
        };
        
        // 文件下载地址回调
        NSURL *(^destinationBlock)(NSURL *, NSURLResponse *) = ^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
            QGStrongify(self);
            
            NSString *cachedFilePath = [self cachedFilePathWithURLString:URLString];
            return [NSURL fileURLWithPath:cachedFilePath];
        };
        
        // 完成回调
        void (^completionBlock)(NSURLResponse *, NSURL *, NSError *) = ^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
            QGStrongify(self);
            
            dispatch_async(self.responseQueue, ^{
                QGStrongify(self);
                
                NSString *cachedFilePath = [self cachedFilePathWithURLString:URLString];
                if (error == nil) {
                    NSAssert([filePath.path isEqual:cachedFilePath] , @"下载文件路径异常!");
                }
                
                if (mergedTask != nil && mergedTask == [self safelyRemoveMergedTaskWithURLIdentifier:URLString]) {
                    for (QGFileDownloaderResponseHandler *responseHandler in mergedTask.responseHandlers) {
                        NSError *finalError = error;
                        if (finalError == nil && [NSFileManager.defaultManager fileExistsAtPath:cachedFilePath]) {
                            // 必要时, 创建目标路径的父文件夹
                            NSString *destPathParentPath = [responseHandler.destinationPath stringByDeletingLastPathComponent];
                            if (![NSFileManager.defaultManager fileExistsAtPath:destPathParentPath]) {
                                [NSFileManager.defaultManager createDirectoryAtPath:destPathParentPath withIntermediateDirectories:YES attributes:nil error:nil];
                            }
                            // 下载成功, 创建文件硬链接
                            [NSFileManager.defaultManager linkItemAtPath:cachedFilePath toPath:responseHandler.destinationPath error:&finalError];
                            // 如果有断点续传数据, 则删除
                            [self removeCachedResumeDataWithURLString:URLString];
                            
                            if (finalError != nil) {
                                NSLog(@"%@", finalError);
                            }
                        }
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (responseHandler.completionBlock) {
                                responseHandler.completionBlock(finalError);
                            }
                        });
                    }
                }
                
                if (error != nil && error.code != NSURLErrorCancelled) {
                    // 下载失败时, 需要删除下载不完整的文件.
                    [self removeCachedFileWithURLString:URLString];
                }
                
                [self safelyDecrementActiveTaskCount];
                [self safelyStartNextTaskIfNecessary];
            });
        };
        
        // 检查是否有断点续传数据 + 对应的未完成下载文件, 区分处理
        BOOL hasCachedResumeData = [self hasCachedResumeDataWithURLString:URLString];
        BOOL hasUnfinishedFile = [self hasUnfinishedFileWithURLString:URLString];
        
        // 无法进行断点续传, 则将对应数据删除
        if (hasCachedResumeData && !hasUnfinishedFile) {
            [self removeCachedResumeDataWithURLString:URLString];
        }
        
        // 创建下载任务(NSURLSessionDownloadTask)
        if (hasCachedResumeData && hasUnfinishedFile) {
            NSData *resumeData = [self cachedResumeDataWithURLString:URLString];
            task = [self.sessionManager downloadTaskWithResumeData:resumeData progress:progressBlock destination:destinationBlock completionHandler:completionBlock];
        } else {
            NSError *serializationError = nil;
            NSMutableURLRequest *request = [self.sessionManager.requestSerializer requestWithMethod:@"GET" URLString:URLString parameters:nil error:&serializationError];
            
            /// 额外的请求头信息
            for (NSString *headerField in headers) {
                [request setValue:headers[headerField] forHTTPHeaderField:headerField];
            }
            
            if (serializationError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(serializationError);
                    }
                });
                return;
            }
            
            if (removeCachedResponse) {
                [[self.class defaultURLCache] removeCachedResponseForRequest:request];
            }
            
            task = [self.sessionManager downloadTaskWithRequest:request progress:progressBlock destination:destinationBlock completionHandler:completionBlock];
        }
        
        // 创建下载完成处理对象
        QGFileDownloaderResponseHandler *responseHandler = [[QGFileDownloaderResponseHandler alloc] initWithHandlerID:handlerID
                                                                                                      destinationPath:destPath
                                                                                                        progressBlock:progress
                                                                                                      completionBlock:completion];
        // 创建可合并的下载任务
        mergedTask = [[QGFileDownloaderMergedTask alloc] initWithURLIdentifier:URLString
                                                                        taskID:NSUUID.UUID
                                                                          task:task];
        [mergedTask addResponseHandler:responseHandler];
        
        // 添加下载任务
        self.mergedTasks[URLString] = mergedTask;
        
        // 开始下载 或 将下载任务加入等待下载的队列
        if ([self isActiveRequestCountBelowMaximumLimit]) {
            [self startMergedTask:mergedTask];
        } else {
            [self enqueueMergedTask:mergedTask];
        }
    });
    
    /* 下载任务创建成功则返回任务清单, 否则返回空 */
    if (task) {
        return [[QGFileDownloadReceipt alloc] initWithReceiptID:handlerID URLString:URLString];
    } else {
        return nil;
    }
}

#pragma mark - 下载参数检查

/**
 检查传入的下载地址和目标存放路径是否合法
 */
- (nullable NSError *)checkDownloadURLString:(NSString *)URLString destinationPath:(NSString *)destPath {
    NSError *error = nil;
    NSString *failureReason = @"";
    
    // 下载到的目标地址检查
    BOOL destPathOK = YES;
    if (QGIsEmpty(destPath)) {
        
        destPathOK = NO;
    } else {
        NSString *destPathParentPath = [destPath stringByDeletingLastPathComponent];
        if ([destPathParentPath containsString:NSHomeDirectory()]) {
            // 当前使用用户有权限生成并写入对应的文件夹.
            destPathOK = YES;
        } else {
            destPathOK = NO;
        }
    }
    
    if (!destPathOK) {
        failureReason = [failureReason stringByAppendingString:@"目标路径不合法"];
    }
    
    // 下载链接格式检查
    if (QGIsEmpty(URLString) || ([URLString isKindOfClass:NSString.class] && ![URLString hasPrefix:@"http"])) {
        if (!destPathOK) {
            failureReason = [failureReason stringByAppendingString:@", 且"];
        }
        failureReason = [failureReason stringByAppendingString:@"下载链接不合法"];
    }
    
    if (failureReason.length > 0) {
        error = [NSError errorWithDomain:QGFileDownloaderDomain
                                    code:NSURLErrorBadURL
                                userInfo:@{NSLocalizedFailureReasonErrorKey : failureReason}];
    }
    
    return error;
}

#pragma mark - 取消任务

- (void)cancelTaskForFileDownloadReceipt:(QGFileDownloadReceipt *)downloadReceipt
{
    [self cancelTaskForFileDownloadReceipt:downloadReceipt keepResumeData:YES];
}

- (void)cancelTaskForFileDownloadReceipt:(QGFileDownloadReceipt *)downloadReceipt
                          keepResumeData:(BOOL)keepResumeData
{
    QGWeakify(self);
    
    dispatch_sync(_synchronizationQueue, ^{
        NSString *URLString = downloadReceipt.URLString;
        if (URLString == nil) {
            return;
        }
        
        QGFileDownloaderMergedTask *mergedTask = self.mergedTasks[URLString];
        if (mergedTask != nil) {
            QGFileDownloaderResponseHandler *responseHandler = [mergedTask responseHandlerWithHandlerID:downloadReceipt.receiptID];
            if (responseHandler != nil) {
                [mergedTask removeResponseHandler:responseHandler];
                
                NSString *failureReason = [NSString stringWithFormat:@"取消下载:%@", URLString];
                NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey:failureReason};
                NSError *error = [NSError errorWithDomain:QGFileDownloaderDomain code:NSURLErrorCancelled userInfo:userInfo];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (responseHandler.completionBlock) {
                        responseHandler.completionBlock(error);
                    }
                });
            }
            
            if (mergedTask.responseHandlers.count == 0) {
                if (keepResumeData) {
                    [mergedTask.task cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
                        // 生成断点续传数据成功时, 保存该数据
                        if (resumeData) {
                            dispatch_async(self.synchronizationQueue, ^{
                                QGStrongify(self);
                                [self cacheResumeData:resumeData withURLString:URLString];
                            });
                        }
                    }];
                } else {
                    [mergedTask.task cancel];
                }
                
                [self removeMergedTaskWithURLIdentifier:URLString];
            }
        }
    });
}

#pragma mark - 下载任务管理

- (QGFileDownloaderMergedTask*)safelyRemoveMergedTaskWithURLIdentifier:(NSString *)URLIdentifier {
    __block QGFileDownloaderMergedTask *mergedTask = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        mergedTask = [self removeMergedTaskWithURLIdentifier:URLIdentifier];
    });
    return mergedTask;
}

// This method should only be called from safely within the synchronizationQueue
- (QGFileDownloaderMergedTask *)removeMergedTaskWithURLIdentifier:(NSString *)URLIdentifier {
    QGFileDownloaderMergedTask *mergedTask = self.mergedTasks[URLIdentifier];
    [self.mergedTasks removeObjectForKey:URLIdentifier];
    return mergedTask;
}

- (void)safelyDecrementActiveTaskCount {
    dispatch_sync(_synchronizationQueue, ^{
        if (self.activeRequestCount > 0) {
            self.activeRequestCount -= 1;
        }
    });
}

- (void)safelyStartNextTaskIfNecessary {
    dispatch_sync(_synchronizationQueue, ^{
        if ([self isActiveRequestCountBelowMaximumLimit]) {
            while (self.queuedMergedTasks.count > 0) {
                QGFileDownloaderMergedTask *mergedTask = [self dequeueMergedTask];
                if (mergedTask.task.state == NSURLSessionTaskStateSuspended) {
                    [self startMergedTask:mergedTask];
                    break;
                }
            }
        }
    });
}

- (void)startMergedTask:(QGFileDownloaderMergedTask *)mergedTask {
    [mergedTask.task resume];
    ++self.activeRequestCount;
}

- (void)enqueueMergedTask:(QGFileDownloaderMergedTask *)mergedTask {
    [self.queuedMergedTasks addObject:mergedTask];
}

- (QGFileDownloaderMergedTask *)dequeueMergedTask {
    QGFileDownloaderMergedTask *mergedTask = nil;
    mergedTask = [self.queuedMergedTasks firstObject];
    [self.queuedMergedTasks removeObject:mergedTask];
    return mergedTask;
}

- (BOOL)isActiveRequestCountBelowMaximumLimit {
    return self.activeRequestCount < self.maximumActiveDownloads;
}

#pragma mark - 缓存文件夹

/**
 下载缓存目录
 */
+ (NSString *)sharedCacheDirectory {
    static NSString *cacheDirectory = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        cacheDirectory = [[paths objectAtIndex:0] stringByAppendingPathComponent:QGFileDownloaderDomain];
    });
    
    if (![NSFileManager.defaultManager fileExistsAtPath:cacheDirectory]) {
        [NSFileManager.defaultManager createDirectoryAtPath:cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return cacheDirectory;
}

- (NSString *)encodedFileNameWithURLString:(NSString *)URLString {
    return [URLString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@".:/%"].invertedSet];
}

#pragma mark - 已下载文件缓存

- (NSString *)cachedFilePathWithURLString:(NSString *)URLString {
    NSString *fileName = [self encodedFileNameWithURLString:URLString];
    return [self.class.sharedCacheDirectory stringByAppendingPathComponent:fileName];
}

- (BOOL)linkCachedFileWithURLString:(NSString *)URLString toTargetPath:(NSString *)targetPath {
    NSString *cachedFilePath = [self cachedFilePathWithURLString:URLString];
    NSError *error = nil;
    BOOL result = [NSFileManager.defaultManager linkItemAtPath:cachedFilePath toPath:targetPath error:&error];
    
    if (error != nil) {
        NSLog(@"%@", error);
    }
    
    return result;
}

- (BOOL)hasCachedFileWithURLString:(NSString *)URLString {
    NSString *cachedFilePath = [self cachedFilePathWithURLString:URLString];
    return [NSFileManager.defaultManager fileExistsAtPath:cachedFilePath];
}

- (void)removeCachedFileWithURLString:(NSString *)URLString {
    NSString *cachedFilePath = [self cachedFilePathWithURLString:URLString];
    [NSFileManager.defaultManager removeItemAtPath:cachedFilePath error:nil];
}

#pragma mark - 断点续传数据缓存

- (NSString *)cachedResumeDataFilePathWithURLString:(NSString *)URLString {
    NSString *cachedResumeDataFilePath = [self cachedFilePathWithURLString:URLString];
    return [cachedResumeDataFilePath stringByAppendingString:@"-ResumeData"];
}

- (NSData *)cachedResumeDataWithURLString:(NSString *)URLString {
    NSString *cachedResumeDataFilePath = [self cachedResumeDataFilePathWithURLString:URLString];
    NSData *resumeData = [NSFileManager.defaultManager contentsAtPath:cachedResumeDataFilePath];
    return resumeData;
}

- (BOOL)hasCachedResumeDataWithURLString:(NSString *)URLString {
    NSString *cachedResumeDataFilePath = [self cachedResumeDataFilePathWithURLString:URLString];
    return [NSFileManager.defaultManager fileExistsAtPath:cachedResumeDataFilePath];
}

- (void)cacheResumeData:(NSData *)resumeData withURLString:(NSString *)URLString {
    NSString *cachedResumeDataFilePath = [self cachedResumeDataFilePathWithURLString:URLString];
    [resumeData writeToFile:cachedResumeDataFilePath atomically:NO];
}

- (void)removeCachedResumeDataWithURLString:(NSString *)URLString {
    NSString *cachedResumeDataFilePath = [self cachedResumeDataFilePathWithURLString:URLString];
    [NSFileManager.defaultManager removeItemAtPath:cachedResumeDataFilePath error:nil];
}

#pragma mark - 未下载完成的文件缓存

/**
 未下载完成的文件缓存路径, 直接放在 tmp 文件夹, 由系统决定何时删除.
 */
- (NSString *_Nullable)unfinishedFilePathWithURLString:(NSString *)URLString {
    NSData *resumeData = [self cachedResumeDataWithURLString:URLString];
    if (resumeData == nil) {
        return nil;
    }
    
    NSString *filename = nil;
    NSError *error = nil;
    NSDictionary *resumeInfo = [NSPropertyListSerialization propertyListWithData:resumeData
                                                                         options:NSPropertyListImmutable
                                                                          format:nil
                                                                           error:&error];
    if (error != nil) {
        NSLog(@"%@", error);
        return nil;
    }
    
    if (![resumeInfo isKindOfClass:NSDictionary.class]) {
        NSLog(@"恢复数据格式错误!");
        return nil;
    }
    
    /** 获取临时文件名 */
    if (NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_8_4) {
        filename = resumeInfo[@"NSURLSessionResumeInfoLocalPath"];// iOS 8
    } else {
        filename = resumeInfo[@"NSURLSessionResumeInfoTempFileName"];// iOS 9
    }
    // iOS 10之后
    if (filename == nil && resumeInfo[@"$objects"] != nil) {
        NSArray *objects = resumeInfo[@"$objects"];
        if ([objects isKindOfClass:NSArray.class]) {
            for (id object in objects) {
                if ([object isKindOfClass:NSString.class]) {
                    BOOL hasTmpSuffix = [(NSString *)object hasSuffix:@".tmp"];
                    BOOL hasCFNetworkPrefix = [(NSString *)object hasPrefix:@"CFNetworkDownload_"];
                    if (hasTmpSuffix && hasCFNetworkPrefix) {
                        filename = object;
                        break;
                    }
                }
            }
        }
    }
    
    if (filename == nil) {
        return nil;
    }
    return [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
}

- (BOOL)hasUnfinishedFileWithURLString:(NSString *)URLString {
    NSString *unfinishedFilePath = [self unfinishedFilePathWithURLString:URLString];
    return [NSFileManager.defaultManager fileExistsAtPath:unfinishedFilePath];
}

#pragma mark - 清空缓存的下载文件

- (void)cleanCachedFilesCompletion:(dispatch_block_t)completion {
    dispatch_async(_synchronizationQueue, ^{
        NSString *cacheDirectory = [self.class sharedCacheDirectory];
        [NSFileManager.defaultManager removeItemAtPath:cacheDirectory error:nil]; // 删除缓存文件目录
        [self.class sharedCacheDirectory];// 重新生成缓存文件目录
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion();
            }
        });
    });
}

- (void)cleanCachedFileWithURLString:(NSString *)URLString completion:(dispatch_block_t)completion  {
    dispatch_async(_synchronizationQueue, ^{
        if ([self hasCachedFileWithURLString:URLString]) {
            [self removeCachedFileWithURLString:URLString];
        }
        if ([self hasCachedResumeDataWithURLString:URLString]) {
            [self removeCachedResumeDataWithURLString:URLString];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion();
            }
        });
    });
}

@end

NS_ASSUME_NONNULL_END
