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
- (nullable NSString *)ftpCurrentDirectory;
- (nullable NSArray<NppFtpEntry *> *)ftpListCurrentDirectory;
- (BOOL)ftpChangeDirectory:(NSString *)path;

// Files
/// Downloads the file and opens it in a tab, remembering where it came from.
- (BOOL)openRemoteFileAtPath:(NSString *)path;
/// Uploads the current document back to where it was opened from.
- (BOOL)uploadCurrentDocument;
/// The remote path a document was opened from, or nil for a local one.
- (nullable NSString *)remotePathForCurrentDocument;

@end

NS_ASSUME_NONNULL_END
