// The FTP side of the editor: saved connections, opening a remote file into a
// tab, and saving it back.
#import "EditorController.h"
#import "FtpClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface EditorController (FtpCommands)

// Profiles
- (NSArray<NppFtpProfile *> *)ftpProfiles;
- (void)saveFtpProfile:(NppFtpProfile *)profile;
- (void)removeFtpProfileNamed:(NSString *)name;
- (nullable NppFtpProfile *)ftpProfileNamed:(NSString *)name;

// Connection
- (BOOL)connectToFtpProfile:(NppFtpProfile *)profile;
/// Connects with a password given directly rather than from the Keychain.
- (BOOL)connectToFtpProfile:(NppFtpProfile *)profile password:(nullable NSString *)password;
- (void)disconnectFtp;
- (BOOL)ftpConnected;
- (nullable NppFtpClient *)ftpClient;
/// Why the last Connect failed (the transfer's own message); nil after a success.
- (nullable NSString *)ftpConnectError;
- (nullable NSString *)ftpCurrentDirectory;
- (nullable NSArray<NppFtpEntry *> *)ftpListCurrentDirectory;
- (BOOL)ftpChangeDirectory:(NSString *)path;
// The same four with the transfer off the main thread and `completion` called on
// it afterwards - what the menu uses, so a slow server does not stop the editor.
- (void)connectToFtpProfile:(NppFtpProfile *)profile password:(nullable NSString *)password
                 completion:(void (^)(BOOL connected, NSArray<NppFtpEntry *> *_Nullable entries))completion;
- (void)ftpListCurrentDirectoryCompletion:(void (^)(NSArray<NppFtpEntry *> *_Nullable entries))completion;
/// Lists the directory once: the listing that shows it exists is the one returned.
- (void)ftpChangeDirectory:(NSString *)path completion:(void (^)(NSArray<NppFtpEntry *> *_Nullable entries))completion;

// Files
/// Downloads the file and opens it in a tab, remembering where it came from.
- (BOOL)openRemoteFileAtPath:(NSString *)path;
- (void)openRemoteFileAtPath:(NSString *)path completion:(void (^)(BOOL opened))completion;
/// Uploads the current document back to where it was opened from.
- (BOOL)uploadCurrentDocument;
- (void)uploadCurrentDocumentCompletion:(void (^)(BOOL uploaded, NSString *_Nullable remote))completion;
/// The remote path a document was opened from, or nil for a local one.
- (nullable NSString *)remotePathForCurrentDocument;

@end

NS_ASSUME_NONNULL_END
