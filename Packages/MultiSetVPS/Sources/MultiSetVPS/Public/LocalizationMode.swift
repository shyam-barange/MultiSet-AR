/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

/// Localization mode enumeration
/// Determines whether to use single-frame or multi-frame localization
public enum LocalizationMode: String, CaseIterable, Identifiable, Sendable {
    case singleFrame = "Single Frame"
    case multiFrame = "Multi Frame"

    public var id: String { rawValue }

    /// Description for display
    public var description: String {
        switch self {
        case .singleFrame:
            return "Capture single frame for quick localization"
        case .multiFrame:
            return "Capture multiple frames for accurate localization"
        }
    }
}
