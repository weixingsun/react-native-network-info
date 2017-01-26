//
//  RNNetworkInfo.m
//  RNNetworkInfo
//
//  Created by Corey Wilson on 7/12/15.
//  Copyright (c) 2015 eastcodes. All rights reserved.
//

#import "RNNetworkInfo.h"

#import <ifaddrs.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netdb.h>
#include <stdio.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <string.h>

#if TARGET_IPHONE_SIMULATOR
#include <net/route.h>
#else
#include "route.h"
#endif

#define CTL_NET 4               /* network, see socket.h */
#define ROUNDUP(a) \
((a) > 0 ? (1 + (((a) - 1) | (sizeof(long) - 1))) : sizeof(long))

@import SystemConfiguration.CaptiveNetwork;

/*
http://stackoverflow.com/questions/35677731/how-to-get-router-ip-address-in-swift-or-objective-c
*/
static int getdefaultgateway(in_addr_t * addr)
{
    int mib[] = {CTL_NET, PF_ROUTE, 0, AF_INET,
        NET_RT_FLAGS, RTF_GATEWAY};
    size_t l;
    char * buf, * p;
    struct rt_msghdr * rt;
    struct sockaddr * sa;
    struct sockaddr * sa_tab[RTAX_MAX];
    int i;
    int r = -1;
    if(sysctl(mib, sizeof(mib)/sizeof(int), 0, &l, 0, 0) < 0) {
        return -1;
    }
    if(l>0) {
        buf = malloc(l);
        if(sysctl(mib, sizeof(mib)/sizeof(int), buf, &l, 0, 0) < 0) {
            return -1;
        }
        for(p=buf; p<buf+l; p+=rt->rtm_msglen) {
            rt = (struct rt_msghdr *)p;
            sa = (struct sockaddr *)(rt + 1);
            for(i=0; i<RTAX_MAX; i++) {
                if(rt->rtm_addrs & (1 << i)) {
                    sa_tab[i] = sa;
                    sa = (struct sockaddr *)((char *)sa + ROUNDUP(sa->sa_len));
                } else {
                    sa_tab[i] = NULL;
                }
            }

            if( ((rt->rtm_addrs & (RTA_DST|RTA_GATEWAY)) == (RTA_DST|RTA_GATEWAY))
               && sa_tab[RTAX_DST]->sa_family == AF_INET
               && sa_tab[RTAX_GATEWAY]->sa_family == AF_INET) {


                if(((struct sockaddr_in *)sa_tab[RTAX_DST])->sin_addr.s_addr == 0) {
                    char ifName[128];
                    if_indextoname(rt->rtm_index,ifName);

                    if(strcmp("en0",ifName)==0){

                        *addr = ((struct sockaddr_in *)(sa_tab[RTAX_GATEWAY]))->sin_addr.s_addr;
                        r = 0;
                    }
                }
            }
        }
        free(buf);
    }
    return r;
}


/*! Returns the string representation of the supplied address.
 *  \param address Contains a (struct sockaddr) with the address to render.
 *  \returns A string representation of that address.
 */

static NSString * displayAddressForAddress(NSData * address) {
    int         err;
    NSString *  result;
    char        hostStr[NI_MAXHOST];
    
    result = nil;
    
    if (address != nil) {
        err = getnameinfo(address.bytes, (socklen_t) address.length, hostStr, sizeof(hostStr), NULL, 0, NI_NUMERICHOST);
        if (err == 0) {
            result = @(hostStr);
        }
    }
    
    if (result == nil) {
        result = @"?";
    }
    
    return result;
}

/*! Returns a short error string for the supplied error.
 *  \param error The error to render.
 *  \returns A short string representing that error.
 */

static NSString * shortErrorFromError(NSError * error) {
    NSString *      result;
    NSNumber *      failureNum;
    int             failure;
    const char *    failureStr;
    
    assert(error != nil);
    
    result = nil;
    
    // Handle DNS errors as a special case.
    
    if ( [error.domain isEqual:(NSString *)kCFErrorDomainCFNetwork] && (error.code == kCFHostErrorUnknown) ) {
        failureNum = error.userInfo[(id) kCFGetAddrInfoFailureKey];
        if ( [failureNum isKindOfClass:[NSNumber class]] ) {
            failure = failureNum.intValue;
            if (failure != 0) {
                failureStr = gai_strerror(failure);
                if (failureStr != NULL) {
                    result = @(failureStr);
                }
            }
        }
    }
    
    // Otherwise try various properties of the error object.
    
    if (result == nil) {
        result = error.localizedFailureReason;
    }
    if (result == nil) {
        result = error.localizedDescription;
    }
    assert(result != nil);
    return result;
}


@implementation RNNetworkInfo

- (void)dealloc {
    [self.pinger stop];
    [self.sendTimer invalidate];
    // self.target = nil;
    // [super dealloc];
}


RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(getSSID:(RCTResponseSenderBlock)callback)
{
    NSArray *interfaceNames = CFBridgingRelease(CNCopySupportedInterfaces());
    NSLog(@"%s: Supported interfaces: %@", __func__, interfaceNames);

    NSDictionary *SSIDInfo;
    NSString *SSID = @"error";

    for (NSString *interfaceName in interfaceNames) {
        SSIDInfo = CFBridgingRelease(CNCopyCurrentNetworkInfo((__bridge CFStringRef)interfaceName));

        if (SSIDInfo.count > 0) {
            SSID = SSIDInfo[@"SSID"];
            break;
        }
    }

    callback(@[SSID]);
}

RCT_EXPORT_METHOD(getIPAddress:(RCTResponseSenderBlock)callback)
{
    NSString *address = @"error";

    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;

    success = getifaddrs(&interfaces);

    if (success == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }

    freeifaddrs(interfaces);
    callback(@[address]);
}

RCT_EXPORT_METHOD(getRouterIPAddress:(RCTResponseSenderBlock)callback)
{
    struct in_addr gatewayaddr;
    int r = getdefaultgateway(&(gatewayaddr.s_addr));
    NSString *routerIPAddress = @"error";
    if (r >= 0) {
        routerIPAddress = [NSString stringWithFormat: @"%s",inet_ntoa(gatewayaddr)];
    }
    callback(@[routerIPAddress]);
}

RCT_EXPORT_METHOD(ping:(NSString *)hostName callback:(RCTResponseSenderBlock)callback)
{
    self.pinger = [[SimplePing alloc] initWithHostName:hostName];
    self.pinger.delegate = self;
    self.callback = callback;
    
    [self.pinger start];
    
    do {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    } while (self.pinger != nil);
}

RCT_EXPORT_METHOD(wake:(NSString *)mac ip:(NSString *)ip callback:(RCTResponseSenderBlock)callback)
{
    NSString *formattedMac = @"error";

	unsigned char *broadcast_addr = (unsigned char*)[ip UTF8String];
    unsigned char *mac_addr = (unsigned char*)[mac UTF8String];

    if (send_wol_packet(broadcast_addr, mac_addr)) {
        formattedMac = @"ok";
    }

    // struct ifaddrs *interfaces = NULL;
    // struct ifaddrs *temp_addr = NULL;
    // int success = 0;

    // success = getifaddrs(&interfaces);

    // if (success == 0) {
    //     temp_addr = interfaces;
    //     while(temp_addr != NULL) {
    //         if(temp_addr->ifa_addr->sa_family == AF_INET) {
    //             if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
    //                 address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
    //             }
    //         }
    //         temp_addr = temp_addr->ifa_next;
    //     }
    // }

    // freeifaddrs(interfaces);

    callback(@[formattedMac]);
}

- (void)sendPing {
    assert(self.pinger != nil);
    [self.pinger sendPingWithData:nil];
}

- (void)simplePing:(SimplePing *)pinger didStartWithAddress:(NSData *)address {
#pragma unused(pinger)
    assert(pinger == self.pinger);
    assert(address != nil);
    
    NSLog(@"pinging %@", displayAddressForAddress(address));
    
    // Send the first ping straight away.
    [self sendPing];
    
    // // And start a timer to send the subsequent pings.
    //
    // assert(self.sendTimer == nil);
    // self.sendTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(sendPing) userInfo:nil repeats:YES];
}

- (void)simplePing:(SimplePing *)pinger didFailWithError:(NSError *)error {
#pragma unused(pinger)
    assert(pinger == self.pinger);
    NSLog(@"failed: %@", shortErrorFromError(error));
    
    // [self.sendTimer invalidate];
    // self.sendTimer = nil;
    
    // No need to call -stop.  The pinger will stop itself in this case.
    // We do however want to nil out pinger so that the runloop stops.
    
    bool found = false;
    self.callback(@[@(found)]);
    
    [self.sendTimer invalidate];
    self.sendTimer = nil;
    self.pinger = nil;
}

- (void)simplePing:(SimplePing *)pinger didSendPacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber {
#pragma unused(pinger)
    assert(pinger == self.pinger);
#pragma unused(packet)
    NSLog(@"#%u sent", (unsigned int) sequenceNumber);
    
    assert(self.sendTimer == nil);
    self.sendTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timerFired:) userInfo:nil repeats:NO];
}

- (void)simplePing:(SimplePing *)pinger didFailToSendPacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber error:(NSError *)error {
#pragma unused(pinger)
    assert(pinger == self.pinger);
#pragma unused(packet)
    NSLog(@"#%u send failed: %@", (unsigned int) sequenceNumber, shortErrorFromError(error));
    
    bool found = false;
    self.callback(@[@(found)]);
    
    [self.sendTimer invalidate];
    self.sendTimer = nil;
    self.pinger = nil;
}

- (void)simplePing:(SimplePing *)pinger didReceivePingResponsePacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber {
#pragma unused(pinger)
    assert(pinger == self.pinger);
#pragma unused(packet)
    NSLog(@"#%u received, size=%zu", (unsigned int) sequenceNumber, (size_t) packet.length);
    
    bool found = true;
    self.callback(@[@(found)]);
    
    [self.sendTimer invalidate];
    self.sendTimer = nil;
    self.pinger = nil;
}

- (void)simplePing:(SimplePing *)pinger didReceiveUnexpectedPacket:(NSData *)packet {
#pragma unused(pinger)
    assert(pinger == self.pinger);
    
    NSLog(@"unexpected packet, size=%zu", (size_t) packet.length);
    
    bool found = false;
    self.callback(@[@(found)]);
    
    [self.sendTimer invalidate];
    self.sendTimer = nil;
    self.pinger = nil;
}

- (void)timerFired:(NSTimer *)timer {
    NSLog(@"ping timeout occurred, host not reachable");
    // Move to next host
    
    bool found = false;
    self.callback(@[@(found)]);
    
    [self.sendTimer invalidate];
    self.sendTimer = nil;
    self.pinger = nil;
}

@end
