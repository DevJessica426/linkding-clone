import 'package:dust_dart/http.dart';

import '../models/bookmark.dart';
import '../models/bundle.dart';
import '../models/inputs.dart';
import '../models/profile.dart';
import '../models/tag.dart';

part 'linkding_api.g.dart';

/// linkding's REST API, as a typed client.
///
/// The paths and parameters are linkding's own (docs/api.md), so the same
/// client talks to a real linkding and to this clone; the parity suite relies
/// on it. Paths are appended to `Dio.options.baseUrl`: point it at
/// `https://host/api`. Authentication is a header set on the Dio instance;
/// see `LinkdingClient`.
@HttpClient(generateTest: true)
abstract interface class LinkdingApi {
  factory LinkdingApi(Dio dio, {String? baseUrl}) = _$LinkdingApi;

  // --- Bookmarks ---

  /// Unarchived bookmarks, newest first unless [sort] says otherwise.
  @GET('/bookmarks/')
  Future<BookmarkPage> bookmarks({
    @Query('q') String? q,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
    @Query('sort') String? sort,
    @Query('modified_since') String? modifiedSince,
    @Query('added_since') String? addedSince,
    @Query('bundle') int? bundle,
  });

  @GET('/bookmarks/archived/')
  Future<BookmarkPage> archivedBookmarks({
    @Query('q') String? q,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
    @Query('sort') String? sort,
    @Query('bundle') int? bundle,
  });

  /// Bookmarks their owners share. Works without a token for owners who
  /// enabled public sharing.
  @GET('/bookmarks/shared/')
  Future<BookmarkPage> sharedBookmarks({
    @Query('q') String? q,
    @Query('user') String? user,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @GET('/bookmarks/{id}/')
  Future<Bookmark> bookmark(@Path() int id);

  @GET('/bookmarks/check/')
  Future<CheckResult> check(@Query('url') String url);

  /// Creates a bookmark, or updates the one already saved for the same URL.
  ///
  /// Pass an empty [disableScraping] to keep an empty title and description
  /// empty instead of filling them in from the page.
  @POST('/bookmarks/')
  Future<Bookmark> createBookmark(
    @Body() BookmarkInput input, {
    @Query('disable_scraping') String? disableScraping,
  });

  @PUT('/bookmarks/{id}/')
  Future<Bookmark> updateBookmark(@Path() int id, @Body() BookmarkInput input);

  /// Changes only the keys present in [changes].
  @PATCH('/bookmarks/{id}/')
  Future<Bookmark> patchBookmark(
    @Path() int id,
    @Body() Map<String, Object?> changes,
  );

  @POST('/bookmarks/{id}/archive/')
  Future<void> archive(@Path() int id);

  @POST('/bookmarks/{id}/unarchive/')
  Future<void> unarchive(@Path() int id);

  @DELETE('/bookmarks/{id}/')
  Future<void> deleteBookmark(@Path() int id);

  // --- Tags ---

  @GET('/tags/')
  Future<TagPage> tags({
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @GET('/tags/{id}/')
  Future<Tag> tag(@Path() int id);

  /// Creates a tag, or returns the existing one with that name in any case.
  @POST('/tags/')
  Future<Tag> createTag(@Body() TagInput input);

  @DELETE('/tags/{id}/')
  Future<void> deleteTag(@Path() int id);

  // --- Bundles ---

  @GET('/bundles/')
  Future<BundlePage> bundles({
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @GET('/bundles/{id}/')
  Future<Bundle> bundle(@Path() int id);

  @POST('/bundles/')
  Future<Bundle> createBundle(@Body() BundleInput input);

  @PUT('/bundles/{id}/')
  Future<Bundle> updateBundle(@Path() int id, @Body() BundleInput input);

  @PATCH('/bundles/{id}/')
  Future<Bundle> patchBundle(
    @Path() int id,
    @Body() Map<String, Object?> changes,
  );

  @DELETE('/bundles/{id}/')
  Future<void> deleteBundle(@Path() int id);

  // --- User ---

  @GET('/user/profile/')
  Future<UserProfile> profile();
}
