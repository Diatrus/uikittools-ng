#include <stdio.h>
#import <getopt.h>
#include <dlfcn.h>
#include <Foundation/Foundation.h>

@interface LSBundleProxy : NSObject
@property (nonatomic, assign, readonly) NSURL *bundleURL;
@property (nonatomic, assign, readonly) NSString *canonicalExecutablePath;
@end

@interface LSApplicationProxy : LSBundleProxy
@property (nonatomic, assign, readonly) NSString *applicationIdentifier;
-(id)localizedNameForContext:(id)context;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(NSDictionary *)options;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleId;
@end

void help(char *name) {
	printf(
		"Usage: %s [OPTION...]\n"
		"Open URLs and open iOS applications by bundle ID\n\n"

		"  <URL>           Open the specified URL\n"
		"                     (replicates the old uiopen behavior)\n"
		"  --url <URL>     Open the specified URL\n"
		"  --bundleid <id> Open application with the\n"
		"                     specified bundle id.\n"
		"  --name <id>     Open application with the\n"
		"                     specified name.\n"
		"  --path <path>   Open application at the specified path\n"
		"  --help          Give this help list.\n", name);
}

int main(int argc, char *argv[]) {
    char *url = NULL;
    char *bundleId = NULL;
    char *name = NULL;
    char *path = NULL;
    int showhelp = 0;

    struct option longOptions[] = {
        { "url" , required_argument, 0, 'u'},
        { "bundleid", required_argument, 0, 'b'},
        { "name", required_argument, 0, 'n'},
        { "path", required_argument, 0, 'p'},
        { "help", no_argument, 0, 'h' },
        { NULL, 0, NULL, 0 }
    };

    int index = 0, code = 0;

    int opterr = 0; // silence getopt errors, allow us to replicate old behaviour

    while ((code = getopt_long(argc, argv, "u:b:n:p:h", longOptions, &index)) != -1) {
        switch (code) {
            case 'u':
                url = strdup(optarg);
                break;
            case 'b':
                bundleId = strdup(optarg);
                break;
            case 'n':
                name = strdup(optarg);
                break;
            case 'p':
                path = strdup(optarg);
                break;
            case 'h':
                showhelp = 1;
                break;
        }
    }

    if (argc == 1) {
        help(argv[0]);
        return 1;
    }

    // replicate old behaviour
    if (!url && !bundleId && !name && !path && !showhelp) {
        url = strdup(argv[1]);
    }

    if (showhelp == 1) {
        help(argv[0]);
    }
    else if (url) {
        NSURL *urlObj = [NSURL URLWithString:[NSString stringWithUTF8String:url]];

        void *fbs = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
        NSString *__strong *FBSOpenApplicationOptionKeyUnlockDevice = (NSString *__strong *)dlsym(fbs, "FBSOpenApplicationOptionKeyUnlockDevice");
        [[LSApplicationWorkspace defaultWorkspace] openSensitiveURL:urlObj withOptions:@{*FBSOpenApplicationOptionKeyUnlockDevice:@YES}];
    }
    else if (bundleId) {
        [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:[NSString stringWithUTF8String:bundleId]];
    }
    else if (name) {
        LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
        NSArray<LSApplicationProxy *> *apps = [workspace allInstalledApplications];

        NSString *nameStr = [NSString stringWithUTF8String:name];

        BOOL found = NO;
        for (LSApplicationProxy *app in apps) {
            if ([nameStr isEqualToString:[app localizedNameForContext:nil]]) {
                [workspace openApplicationWithBundleID:app.applicationIdentifier];
                found = YES;
                break;
            }
        }
        if (!found) {
            fprintf(stderr, "No application called: %s\n", name);
            return 1;
        }
    }
    else if (path) {
        LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
        NSArray<LSApplicationProxy *> *apps = [workspace allInstalledApplications];

		NSString *pathString = [NSString stringWithUTF8String:path];
        NSString *urlString = [@"file://" stringByAppendingString:pathString];

        if (![urlString hasSuffix:@"/"]) {
            urlString = [urlString stringByAppendingString:@"/"];
        }
        NSURL *bundleURL = [NSURL URLWithString:urlString];

        if (bundleURL) {
            BOOL found = NO;
            for (LSApplicationProxy *app in apps) {
                if ([bundleURL isEqual:app.bundleURL] || [pathString isEqualToString:app.canonicalExecutablePath]) {
                    [workspace openApplicationWithBundleID:app.applicationIdentifier];
                    found = YES;
                    break;
                }
            }
            if (!found) {
                fprintf(stderr, "No application at path: %s\n", path);
                return 1;
            }
        } else {
            fprintf(stderr, "Invalid path: %s\n", path);
            return 1;
        }
    }
    return 0;
}
