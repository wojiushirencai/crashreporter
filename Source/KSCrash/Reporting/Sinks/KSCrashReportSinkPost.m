//
//  KSCrashReportSinkVictory.m
//
//  Created by Kelp on 2013-03-14.
//
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//


#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
#import <UIKit/UIKit.h>
#endif
#import "KSCrashReportSinkPost.h"

#import "KSCrashCallCompletion.h"
#import "KSHTTPMultipartPostBody.h"
#import "KSHTTPRequestSender.h"
#import "NSData+GZip.h"
#import "KSJSONCodecObjC.h"
#import "KSReachabilityKSCrash.h"
#import "NSError+SimpleConstructor.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"


@interface KSCrashReportSinkPost ()

@property(nonatomic,readwrite,retain) NSURL* url;
@property(nonatomic,readwrite,retain) NSString* userToken;
@property(nonatomic,readwrite,retain) NSString* userUserId;

@property(nonatomic,readwrite,retain) KSReachableOperationKSCrash* reachableOperation;


@end


@implementation KSCrashReportSinkPost

@synthesize url = _url;
@synthesize userToken = _userToken;
@synthesize userUserId = _userUserId;
@synthesize reachableOperation = _reachableOperation;

+ (KSCrashReportSinkPost*) sinkWithURL:(NSURL*) url
                                   userToken:(NSString*) userToken
                                  userUserId:(NSString*) userUserId
{
    return [[self alloc] initWithURL:url userToken:userToken userUserId:userUserId];
}

- (id) initWithURL:(NSURL*) url
          userToken:(NSString*) userToken
         userUserId:(NSString*) userUserId
{
    if((self = [super init]))
    {
        self.url = url;
        if (userToken == nil || [userToken length] == 0) {
#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
            self.userToken = UIDevice.currentDevice.name;
#else
            self.userToken = @"unknown";
#endif
        }
        else {
            self.userToken = userToken;
        }
        self.userUserId = userUserId;
    }
    return self;
}

- (id <KSCrashReportFilter>) defaultCrashReportFilterSet
{
    return self;
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    // update user information in reports with KVC
    for (NSDictionary *report in reports) {
        NSDictionary *userDict = [report objectForKey:@"user"];
        if (userDict) {
            // user member is exist
            [userDict setValue:self.userToken forKey:@"name"];
            [userDict setValue:self.userUserId forKey:@"email"];
        }
        else {
            // no user member, append user dictionary
            [report setValue:@{@"name": self.userToken, @"email": self.userUserId} forKey:@"user"];
        }
    }
    
    NSError* error = nil;
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:self.url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:15];
    KSHTTPMultipartPostBody* body = [KSHTTPMultipartPostBody body];
    
    NSData* jsonData = [KSJSONCodec encode:reports
                                   options:KSJSONEncodeOptionSorted
                                     error:&error];
    if(jsonData == nil)
    {
        kscrash_i_callCompletion(onCompletion, reports, NO, error);
        return;
    }
    
    [body appendData:[jsonData gzippedWithCompressionLevel:-1 error:nil]
                name:@"reports"
         contentType:@"application/x-www-form-urlencoded"
            filename:@"reports.zip"];
    
    // POST http request
    // Content-Type: multipart/form-data; boundary=xxx
    // Content-Encoding: gzip
    request.HTTPMethod = @"POST";
    request.HTTPBody = [body data];
    [request setValue:body.contentType forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"];
    [request setValue:@"KSCrashReporter" forHTTPHeaderField:@"User-Agent"];
    [request setValue:self.userUserId forHTTPHeaderField:@"userId"];
    [request setValue:self.userToken forHTTPHeaderField:@"token"];
    self.reachableOperation = [KSReachableOperationKSCrash operationWithHost:[self.url host]
                                                                   allowWWAN:YES
                                                                       block:^
    {
        [[KSHTTPRequestSender sender] sendRequest:request
                                        onSuccess:^(__unused NSHTTPURLResponse* response, __unused NSData* data)
         {
             NSString* text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
             NSLog(text);
             kscrash_i_callCompletion(onCompletion, reports, YES, nil);
         } onFailure:^(NSHTTPURLResponse* response, NSData* data)
         {
             NSString* text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
             kscrash_i_callCompletion(onCompletion, reports, NO,
                                      [NSError errorWithDomain:[[self class] description]
                                                          code:response.statusCode
                                                   description:text]);
         } onError:^(NSError* error2)
         {
             kscrash_i_callCompletion(onCompletion, reports, NO, error2);
         }];
    }];
}

@end
