import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';

class SkeletonGameCardHorizontal extends StatelessWidget {
  const SkeletonGameCardHorizontal({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.surfaceHighlight,
      highlightColor: Colors.white12,
      child: Container(
        width: 350,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class SkeletonGameCardVertical extends StatelessWidget {
  const SkeletonGameCardVertical({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.surfaceHighlight,
      highlightColor: Colors.white12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover Image Skeleton
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Title Skeleton
          Container(
            height: 16,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          // Subtitle Skeleton
          Container(
            height: 12,
            width: 80,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
