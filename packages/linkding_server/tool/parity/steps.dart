import 'step.dart';
import 'steps_assets.dart';
import 'steps_create.dart';
import 'steps_lists.dart';
import 'steps_profile_pages.dart';
import 'steps_sharing.dart';
import 'steps_tags_bundles.dart';
import 'steps_update.dart';

/// The API surface, in an order where later steps build on earlier ones.
final steps = <Step>[
  ...createSteps,
  ...updateSteps,
  ...listSteps,
  ...tagBundleSteps,
  ...profilePageSteps,
  ...sharingSteps,
  ...assetSteps,
];
