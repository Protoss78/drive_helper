library drive_helper;

import 'package:flutter/material.dart' show Widget;
import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignIn, GoogleSignInAccount, GoogleUserCircleAvatar;
import 'package:googleapis/drive/v3.dart'
    show DriveApi, File, Media, DownloadOptions;
import 'dart:convert' show ascii;
import 'package:http/http.dart'
    show BaseClient, Client, StreamedResponse, BaseRequest;

/// A [BaseClient] that stores the Google authentication headers,
/// and uses them to authenticate each request
class _GoogleAuthClient extends BaseClient {
  final Map<String, String> _headers;
  final Client _client = Client();

  _GoogleAuthClient(this._headers);

  Future<StreamedResponse> send(BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

/// File MIME types that Google Drive uses
abstract class FileMIMETypes {
  /// # File
  ///
  /// You may provide a file extension with the file name,
  /// and the file type will be automatically inferred.
  ///
  /// For example, if you create a file with this mime type and call it
  /// `test.csv`, it will be automatically converted into a Google Sheets file.
  ///
  /// You can still get back a CSV file by choosing the export type.
  static final file = "application/vnd.google-apps.file";

  /// # Folder
  ///
  /// To put a file in to a folder,
  /// specify the file's parent as the parent folder's file ID.
  static final folder = "application/vnd.google-apps.folder";
}

/// Scopes of data access
///
/// [Official Documentation](https://developers.google.com/drive/api/guides/api-specific-auth#scopes)
abstract class DriveScopes {
  /// See, create, edit, and delete all Google Drive files created by anyone
  ///
  /// WARNING: Only use this if absolutely necessary.
  /// [app] should be enough for most purposes.
  static final full = DriveApi.driveScope;

  /// See, create, edit, and delete all Google Drive files created by this app only
  ///
  /// This is the recommended scope for most apps.
  static final app = DriveApi.driveFileScope;

  /// See, create, edit, and delete files that can only be created and viewed by this app
  ///
  /// Perfect for configuration files, databases, etc.
  ///
  /// Files stored in this special folder cannot be seen by the user,
  /// but can be deleted by them.
  static final appData = DriveApi.driveAppdataScope;

  /// Only read, not edit or create all Google Drive files created by anyone
  static final read = DriveApi.driveReadonlyScope;
}

class DriveHelper {
  /// Internal Google APIs Drive v3 instance
  DriveApi driveAPI;

  /// Signed in Google account
  GoogleSignInAccount account;

  /// Google account sign in configuration settings
  GoogleSignIn signIn;

  /// Signed in Google account's display name, which might not exist
  String? get name => account.displayName;

  /// Signed in Google account's email
  String get email => account.email;

  /// Widget that shows the signed in Google account's avatar
  Widget get avatar => GoogleUserCircleAvatar(identity: account);

  /// Empty constructor
  DriveHelper._construct(this.driveAPI, this.account, this.signIn);

  /// Sign in to Google Drive and intialise [DriveHelper].
  /// Provide [scopes] from [DriveScopes], or custom ones by passing strings.
  ///
  /// Consider using a `FutureBuilder` to
  /// asynchronously await on this method and show a loading screen,
  /// and show an error page if this method fails.
  static Future<DriveHelper> initialise(List<String> scopes) async {
    final signIn = GoogleSignIn.standard(scopes: scopes);

    final account = (await signIn.isSignedIn()
        ? await signIn.signInSilently() ?? await signIn.signIn()
        : await signIn.signIn());

    // ignore: unnecessary_statements
    account == null ? throw "Account authentication failed" : null;

    return DriveHelper._construct(
      DriveApi(_GoogleAuthClient(await account.authHeaders)),
      account,
      signIn,
    );
  }

  /// Mark the current user as being in the signed out state
  ///
  /// You should restart the app afterwards using a package such as
  /// [`flutter_phoenix`](https://pub.dev/packages/flutter_phoenix).
  Future<void> signOut() async => signIn.signOut();

  /// Disconnect the user from the app, and revoke all authentication between
  /// the user and this app
  ///
  /// Requires the user to sign in and accept requested permissions
  /// the next time the user tries to sign in.
  ///
  /// You should restart the app afterwards using a package such as
  /// [`flutter_phoenix`](https://pub.dev/packages/flutter_phoenix).
  Future<void> disconnect() async => signIn.disconnect();

  /// Create a new file with [fileName], and a [mime] type
  /// that is from [FileMIMETypes] or a custom string
  ///
  /// Optionally, specify the ID(s) of the [parents] folder(s).
  ///
  /// You can provide some text to initialise the file with
  /// (e.g. header data or boilerplate)
  ///
  /// Returns the ID of the file created,
  /// store this to refer to this file in the future.
  Future<String> createFile(
    String fileName,
    String mime, {
    List<String>? parents,
    String text = "",
  }) async {
    return (await driveAPI.files.create(
      File(
        name: fileName,
        mimeType: mime,
        parents: parents,
      ),
      uploadMedia: Media(
        Stream.value(ascii.encode(text)),
        text.length,
      ),
    ))
        .id!;
  }

  /// GET the data of [fileID]'s file as a string
  Future<String> getData(String fileID) async {
    final file = await driveAPI.files.get(
      fileID,
      downloadOptions: DownloadOptions.fullMedia,
    ) as Media;

    String fileData = "";
    await file.stream.listen((bytes) {
      fileData += String.fromCharCodes(bytes);
    }).asFuture();
    return fileData;
  }

  /// Append [data] to an existing file of [fileID]
  ///
  /// You may also provide the [mime] type of the format to export the file in,
  /// this defaults to plain text.
  ///
  /// Optionally, you can provide a [seperator] which will be added
  /// between the existing data and the provided [data].
  /// This defaults to a newline `\n`.
  Future<void> appendFile(
    String fileID,
    String data, {
    String mime = "text/plain",
    String seperator = '\n',
  }) async {
    final oldData = (await exportFile(fileID, mime))!;
    updateFile(fileID, oldData + seperator + data);
  }

  /// Deletss the file of [fileID]
  ///
  /// Please use with caution, especially with [DriveScopes.full].
  Future<void> deleteFile(String fileID) => driveAPI.files.delete(fileID);

  /// Overwrite an existing file of [fileID] with new data
  ///
  /// Please use this command with caution,
  /// as this is equivalent to deleting the existing data in the file.
  ///
  /// If you need to append data to the end of a file, use [appendFile].
  Future<void> updateFile(String fileID, String data) => driveAPI.files.update(
        File(),
        fileID,
        uploadMedia: Media(
          Stream.value(ascii.encode(data)),
          data.length,
        ),
      );

  /// Export a Google Workspace file of [fileID] in the provided [mime] type
  Future<String?> exportFile(String fileID, String mime) async {
    final fileMedia = await driveAPI.files.export(
      fileID,
      mime,
      downloadOptions: DownloadOptions.fullMedia,
    );

    String fileData = "";
    await fileMedia!.stream.listen((bytes) {
      fileData += String.fromCharCodes(bytes);
    }).asFuture();
    return fileData;
  }

  /// Get the file ID of a file from its [fileName]
  ///
  /// If multiple files with the same name exist,
  /// their IDs will be returned in a list.
  ///
  /// This only searches for items that are not trashed.
  Future<List<String>> getFileID(String fileName) async {
    final search = await driveAPI.files.list(
      q: "name='$fileName' and trashed=false",
      spaces: "drive" +
          (signIn.scopes.contains(DriveApi.driveAppdataScope)
              ? ", appDataFolder"
              : ""),
    );

    List<String> result = List.empty(growable: true);
    if (search.files == null || search.files!.length == 0) {
      throw "File not found";
    } else {
      search.files!.forEach((file) => result.add(file.id!));
    }
    return result;
  }
}
