//
//  QGFileDownloader.h
//  QGFileDownloader
//
//  Created by QG on 2022/06/29.
//  Forked from AFImageDownloader and modified by QG.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const QGFileDownloaderDomain; ///< 错误定义域名

typedef void(^QGFileDownloadProgressBlock)(NSProgress *);
typedef void(^QGFileDownloadCompletionBlock)(NSError *_Nullable);

/**
 文件下载清单
 */
@interface QGFileDownloadReceipt : NSObject

/**
 该次文件下载的唯一标识
 */
@property (nonatomic, strong, readonly) NSUUID *receiptID;

/**
 文件下载地址
 */
@property (nonatomic, strong, readonly) NSString *URLString;

@end

/**
 下载返回处理器
 */
@interface QGFileDownloaderResponseHandler : NSObject
@end

/**
 可合并的下载任务
 */
@interface QGFileDownloaderMergedTask : NSObject
@end

/**
 文件下载器, 自动管理断点续传.
 被下载文件被视为只读文件, 一个 url 在有缓存的情况下不会重复下载.
 [请使用单例对象]
 */
@interface QGFileDownloader : NSObject

/**
 默认文件下载器(单例)

 @return 默认文件下载器
 */
+ (instancetype)sharedInstance;

/**
 下载文件到目标路径
 参考-downloadFile:destPath:removeCachedResponse:progress:completion:

 @param URLString 文件的网络地址
 @param destPath 文件将下载到的本地目标地址, 必须为完整路径.
 @param completion 完成回调(在主线程执行), 失败返回错误, 成功返回空错误.
 @return 文件下载信息清单, 可用于取消下载.
 */
- (QGFileDownloadReceipt *_Nullable)downloadFile:(nullable NSString *)URLString
                                        destPath:(NSString *)destPath
                                      completion:(QGFileDownloadCompletionBlock _Nullable)completion;
/**
 下载文件到目标路径
 参考-downloadFile:destPath:removeCachedResponse:progress:completion:
 
 @param URLString 文件的网络地址
 @param destPath 文件将下载到的本地目标地址, 必须为完整路径.
 @param progress 进度回调(在主线程执行)
 @param completion 完成回调(在主线程执行), 成功则错误为空, 否则为对应的错误.
 @return 文件下载信息清单, 可用于取消下载.
 */
- (QGFileDownloadReceipt *_Nullable)downloadFile:(NSString *)URLString
                                        destPath:(NSString *)destPath
                                        progress:(QGFileDownloadProgressBlock _Nullable)progress
                                      completion:(QGFileDownloadCompletionBlock _Nullable)completion;

- (QGFileDownloadReceipt *_Nullable)downloadFile:(NSString *)URLString
                                        destPath:(NSString *)destPath
                            removeCachedResponse:(BOOL)removeCachedResponse
                                        progress:(QGFileDownloadProgressBlock _Nullable)progress
                                      completion:(QGFileDownloadCompletionBlock _Nullable)completion;

/**
 下载文件到目标路径
 - 同时多次下载同一个 url 对应的文件, 会进行请求合并.
 - 同时支持最大4个下载任务.
 - 注意: 默认使用缓存. 并且, 如果目标路劲(destPath)下已有对应文件存在, 则认为已下载, 视为缓存的下载文件直接返回成功(这种情况下, 如果调用线程为主线程, 则在主线程下直接返回).
 
 @param URLString 文件的网络地址
 @param destPath 文件将下载到的本地目标地址, 必须为完整路径.
 @param headers 本次下载需要拼接的额外headers
 @param removeCachedResponse 是否清除对应的请求缓存, 如果存在断点续传数据则此变量无效
 @param progress 进度回调(在主线程执行)
 @param completion 完成回调(在主线程执行), 成功则错误为空, 否则为对应的错误
 @return 文件下载信息清单, 可用于取消下载.
 */
- (QGFileDownloadReceipt *_Nullable)downloadFile:(NSString *)URLString
                                        destPath:(NSString *)destPath
                                         headers:(nullable NSDictionary <NSString *, NSString *> *)headers
                            removeCachedResponse:(BOOL)removeCachedResponse
                                        progress:(QGFileDownloadProgressBlock _Nullable)progress
                                      completion:(QGFileDownloadCompletionBlock _Nullable)completion;

/**
 取消下载, 保存断点续传数据.
 如果文件已下载完成或已取消, 则无效果.

 @param downloadReceipt 下载信息清单
 */
- (void)cancelTaskForFileDownloadReceipt:(QGFileDownloadReceipt *)downloadReceipt;

/**
 取消下载
 如果文件已下载完成, 则无效果.

 @param downloadReceipt 下载信息清单
 @param keepResumeData 是否保存断点续传数据
 */
- (void)cancelTaskForFileDownloadReceipt:(QGFileDownloadReceipt *)downloadReceipt
                          keepResumeData:(BOOL)keepResumeData;

/**
 清除所有的下载文件缓存
 
 @param completion 完成回调
 */
- (void)cleanCachedFilesCompletion:(dispatch_block_t)completion;

/**
 清除某个特定的下载文件缓存

 @param URLString 文件的网络地址
 @param completion 完成回调
 */
- (void)cleanCachedFileWithURLString:(NSString *)URLString completion:(dispatch_block_t)completion;

@end

NS_ASSUME_NONNULL_END
