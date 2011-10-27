// clang -framework Foundation -W -Wall -Wno-unused-parameter -g main.m MABlockForwarding.m

#import <stdio.h>

#import "MABlockForwarding.h"


int main(int argc, char **argv)
{
    [NSAutoreleasePool new];
    
    int (^intblock)(int) = MAMemoize(^(int x) {
        NSLog(@"called with %d", x);
        return x + 1;
    });
    
    intblock = [[intblock copy] autorelease];
    
    NSLog(@"%d", intblock(1));
    NSLog(@"%d", intblock(2));
    NSLog(@"%d", intblock(2));
    NSLog(@"%d", intblock(1));
    
    id (^objblock)(NSString *, NSString *) = MAMemoize(^(NSString *a, NSString *b) {
        NSLog(@"called with %@ %@", a, b);
        return [a stringByAppendingString: b];
    });
    
    NSLog(@"%@", objblock(@"hello", @"world"));
    NSLog(@"%@", objblock(@"hi", @"bob"));
    NSLog(@"%@", objblock(@"hi", @"bob"));
    NSLog(@"%@", objblock(@"hello", @"world"));
    
    char *(^cstrblock)(char *, char *) = MAMemoize(^(char *a, char *b) {
        NSLog(@"called with %s %s", a, b);
        return [[NSString stringWithFormat: @"%s%s", a, b] UTF8String];
    });
    
    NSLog(@"%s", cstrblock("hello", "world"));
    NSLog(@"%s", cstrblock("hi", "bob"));
    NSLog(@"%s", cstrblock("hi", "bob"));
    NSLog(@"%s", cstrblock("hello", "world"));
    
    __block uint64_t (^fib)(int) = MAMemoize(^uint64_t (int n) {
        if(n <= 1)
            return 1;
        else
            return fib(n - 1) + fib(n - 2);
    });
    
    for(int i = 0; i < 60; i++)
        NSLog(@"%llu", (unsigned long long)fib(i));
}
