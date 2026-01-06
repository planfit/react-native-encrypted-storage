//
//  RNEncryptedStorage.m
//  Starter
//
//  Created by Yanick Bélanger on 2020-02-09.
//  Copyright © 2020 Facebook. All rights reserved.
//

#import "RNEncryptedStorage.h"
#import <Security/Security.h>
#import <React/RCTLog.h>

void rejectPromise(NSString *message, NSError *error, RCTPromiseRejectBlock rejecter)
{
    NSString* errorCode = [NSString stringWithFormat:@"%ld", error.code];
    NSString* errorMessage = [NSString stringWithFormat:@"RNEncryptedStorageError: %@", message];

    rejecter(errorCode, errorMessage, error);
}

@implementation RNEncryptedStorage

+ (NSString *)getKeychainService
{
    NSString* service = [[NSBundle mainBundle] bundleIdentifier];
    if (service == nil) {
        service = @"com.react-native-encrypted-storage";
    }
    return service;
}

+ (NSString *)getKeychainErrorDescription:(OSStatus)status
{
    switch (status) {
        case errSecSuccess:
            return @"No error";
        case errSecUnimplemented:
            return @"Function or operation not implemented";
        case errSecParam:
            return @"One or more parameters passed to the function were not valid";
        case errSecAllocate:
            return @"Failed to allocate memory";
        case errSecNotAvailable:
            return @"No trust results are available";
        case errSecAuthFailed:
            return @"Authorization and/or authentication failed";
        case errSecDuplicateItem:
            return @"The item already exists";
        case errSecItemNotFound:
            return @"The item cannot be found";
        case errSecInteractionNotAllowed:
            return @"Interaction with the Security Server is not allowed";
        case errSecDecode:
            return @"Unable to decode the provided data";
        case errSecMissingEntitlement:
            return @"Internal error: A required entitlement is missing";
        default:
            return [NSString stringWithFormat:@"Unknown error: %d", (int)status];
    }
}

- (NSString *)getKeychainErrorDescription:(OSStatus)status
{
    return [RNEncryptedStorage getKeychainErrorDescription:status];
}

+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(setItem:(NSString *)key withValue:(NSString *)value resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSData* dataFromValue = [value dataUsingEncoding:NSUTF8StringEncoding];
    
    if (dataFromValue == nil) {
        NSError* error = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:0 userInfo: nil];
        rejectPromise(@"An error occured while parsing value", error, reject);
        return;
    }
    
    NSString* service = [RNEncryptedStorage getKeychainService];
    
    NSDictionary* deleteQueryWithService = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : service,
        (__bridge id)kSecAttrAccount : key
    };
    SecItemDelete((__bridge CFDictionaryRef)deleteQueryWithService);
    
    NSDictionary* deleteQueryWithoutService = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount : key
    };
    SecItemDelete((__bridge CFDictionaryRef)deleteQueryWithoutService);
    
    NSDictionary* storeQuery = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : service,
        (__bridge id)kSecAttrAccount : key,
        (__bridge id)kSecValueData : dataFromValue,
        (__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    };
    
    OSStatus insertStatus = SecItemAdd((__bridge CFDictionaryRef)storeQuery, nil);
    
    if (insertStatus == noErr) {
        resolve(value);
    }
    else {
        NSDictionary* updateQueryWithService = @{
            (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService : service,
            (__bridge id)kSecAttrAccount : key
        };
        
        NSDictionary* updateQueryWithoutService = @{
            (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrAccount : key
        };
        
        NSDictionary* updateAttributes = @{
            (__bridge id)kSecValueData : dataFromValue
        };
        
        NSDictionary* storeQueryNoAccessible = @{
            (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService : service,
            (__bridge id)kSecAttrAccount : key,
            (__bridge id)kSecValueData : dataFromValue
        };
        
        if (insertStatus == errSecInteractionNotAllowed) {
            SecItemDelete((__bridge CFDictionaryRef)deleteQueryWithService);
            SecItemDelete((__bridge CFDictionaryRef)deleteQueryWithoutService);
            
            insertStatus = SecItemAdd((__bridge CFDictionaryRef)storeQueryNoAccessible, nil);
            if (insertStatus == noErr) {
                resolve(value);
                return;
            }
            
            if (insertStatus == errSecDuplicateItem) {
                OSStatus updateStatus = SecItemUpdate((__bridge CFDictionaryRef)updateQueryWithService, (__bridge CFDictionaryRef)updateAttributes);
                if (updateStatus == noErr) {
                    resolve(value);
                    return;
                }
                if (updateStatus == errSecItemNotFound) {
                    updateStatus = SecItemUpdate((__bridge CFDictionaryRef)updateQueryWithoutService, (__bridge CFDictionaryRef)updateAttributes);
                    if (updateStatus == noErr) {
                        resolve(value);
                        return;
                    }
                }
            }
        }
        
        if (insertStatus == errSecDuplicateItem) {
            OSStatus updateStatus = SecItemUpdate((__bridge CFDictionaryRef)updateQueryWithService, (__bridge CFDictionaryRef)updateAttributes);
            
            if (updateStatus == noErr) {
                resolve(value);
                return;
            }
            
            if (updateStatus == errSecItemNotFound) {
                updateStatus = SecItemUpdate((__bridge CFDictionaryRef)updateQueryWithoutService, (__bridge CFDictionaryRef)updateAttributes);
                
                if (updateStatus == noErr) {
                    resolve(value);
                    return;
                }
            }
            
            if (updateStatus != noErr) {
                SecItemDelete((__bridge CFDictionaryRef)updateQueryWithService);
                SecItemDelete((__bridge CFDictionaryRef)updateQueryWithoutService);
                
                insertStatus = SecItemAdd((__bridge CFDictionaryRef)storeQuery, nil);
                if (insertStatus == noErr) {
                    resolve(value);
                    return;
                }
                
                if (insertStatus == errSecInteractionNotAllowed || insertStatus == errSecDuplicateItem) {
                    insertStatus = SecItemAdd((__bridge CFDictionaryRef)storeQueryNoAccessible, nil);
                    if (insertStatus == noErr) {
                        resolve(value);
                        return;
                    }
                    
                    if (insertStatus == errSecDuplicateItem) {
                        updateStatus = SecItemUpdate((__bridge CFDictionaryRef)updateQueryWithService, (__bridge CFDictionaryRef)updateAttributes);
                        if (updateStatus == noErr) {
                            resolve(value);
                            return;
                        }
                        if (updateStatus == errSecItemNotFound) {
                            updateStatus = SecItemUpdate((__bridge CFDictionaryRef)updateQueryWithoutService, (__bridge CFDictionaryRef)updateAttributes);
                            if (updateStatus == noErr) {
                                resolve(value);
                                return;
                            }
                        }
                        insertStatus = updateStatus;
                    }
                }
            } else {
                insertStatus = updateStatus;
            }
        }
        
        NSString* errorDescription = [self getKeychainErrorDescription:insertStatus];
        NSError* error = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] 
                                             code:insertStatus 
                                         userInfo:@{NSLocalizedDescriptionKey: errorDescription}];
        rejectPromise(@"An error occured while saving value", error, reject);
    }
}

RCT_EXPORT_METHOD(getItem:(NSString *)key resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSString* service = [RNEncryptedStorage getKeychainService];
    
    NSDictionary* getQuery = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : service,
        (__bridge id)kSecAttrAccount : key,
        (__bridge id)kSecReturnData : (__bridge id)kCFBooleanTrue,
        (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitOne
    };
    
    CFTypeRef dataRef = NULL;
    OSStatus getStatus = SecItemCopyMatching((__bridge CFDictionaryRef)getQuery, &dataRef);
    
    if (getStatus == errSecSuccess) {
        NSString* storedValue = [[NSString alloc] initWithData: (__bridge NSData*)dataRef encoding: NSUTF8StringEncoding];
        if (dataRef != NULL) {
            CFRelease(dataRef);
        }
        resolve(storedValue);
    }

    else if (getStatus == errSecItemNotFound) {
        resolve(nil);
    }
    
    else {
        NSString* errorDescription = [self getKeychainErrorDescription:getStatus];
        NSError* error = [NSError errorWithDomain: [[NSBundle mainBundle] bundleIdentifier] 
                                             code:getStatus 
                                         userInfo:@{NSLocalizedDescriptionKey: errorDescription}];
        rejectPromise(@"An error occured while retrieving value", error, reject);
    }
}

RCT_EXPORT_METHOD(removeItem:(NSString *)key resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSString* service = [RNEncryptedStorage getKeychainService];
    
    NSDictionary* removeQuery = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : service,
        (__bridge id)kSecAttrAccount : key
    };
    
    OSStatus removeStatus = SecItemDelete((__bridge CFDictionaryRef)removeQuery);
    
    if (removeStatus == noErr || removeStatus == errSecItemNotFound) {
        resolve(key);
    }
    
    else {
        NSString* errorDescription = [self getKeychainErrorDescription:removeStatus];
        NSError* error = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] 
                                             code:removeStatus 
                                         userInfo:@{NSLocalizedDescriptionKey: errorDescription}];
        rejectPromise(@"An error occured while removing value", error, reject);
    }
}

RCT_EXPORT_METHOD(clear:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSArray *secItemClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];
    
    // Maps through all Keychain classes and deletes all items that match
    for (id secItemClass in secItemClasses) {
        NSDictionary *spec = @{(__bridge id)kSecClass: secItemClass};
        SecItemDelete((__bridge CFDictionaryRef)spec);
    }
    
    resolve(nil);
}
@end
