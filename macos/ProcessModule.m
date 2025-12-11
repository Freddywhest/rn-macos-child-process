#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_REMAP_MODULE (ProcessModule, ProcessModule, NSObject)

// Update existing method to include cwd parameter
RCT_EXTERN_METHOD(
    executeCommand : (NSString *)command arguments : (NSArray<NSString *> *)
        arguments cwd : (NSString *)cwd resolver : (RCTPromiseResolveBlock)
            resolve rejecter : (RCTPromiseRejectBlock)reject)

// New methods
RCT_EXTERN_METHOD(getCurrentDirectory : (RCTPromiseResolveBlock)
                      resolve rejecter : (RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(changeDirectory : (NSString *)path resolver : (
    RCTPromiseResolveBlock)resolve rejecter : (RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(executeWithOptions : (NSString *)command arguments : (
    NSArray<NSString *> *)arguments options : (NSDictionary *)
                      options resolver : (RCTPromiseResolveBlock)
                          resolve rejecter : (RCTPromiseRejectBlock)reject)

// Update shell method to include cwd
RCT_EXTERN_METHOD(shell : (NSString *)command cwd : (NSString *)cwd resolver : (
    RCTPromiseResolveBlock)resolve rejecter : (RCTPromiseRejectBlock)reject)

// Keep existing methods
RCT_EXTERN_METHOD(spawnCommand : (NSString *)command arguments : (
    NSArray<NSString *> *)arguments options : (NSDictionary *)
                      options resolver : (RCTPromiseResolveBlock)
                          resolve rejecter : (RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getEnvironment : (RCTPromiseResolveBlock)
                      resolve rejecter : (RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getSystemInfo : (RCTPromiseResolveBlock)
                      resolve rejecter : (RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(killProcess : (NSInteger)pid signal : (NSInteger)
                      signal resolver : (RCTPromiseResolveBlock)
                          resolve rejecter : (RCTPromiseRejectBlock)reject)

@end
