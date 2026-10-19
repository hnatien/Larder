import LarderDesign
import SwiftUI

/// The data source and the full licence of every third-party library and font Larder ships.
struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                SettingsGroup {
                    Text(AccountCopy.Settings.usdaAttribution)
                }
                SettingsGroup(AccountCopy.Settings.grdbLicence) {
                    LicenceText(ThirdPartyLicence.grdb)
                }
                let fontLicences = LarderFont.licenceTexts
                if LarderFont.hasBundledFonts, !fontLicences.isEmpty {
                    SettingsGroup(AccountCopy.Settings.fontLicence) {
                        ForEach(fontLicences, id: \.self) { LicenceText($0) }
                    }
                }
            }
            .padding(LarderSpacing.l)
        }
        .background(LarderColor.surface.canvas)
        .navigationTitle(AccountCopy.Settings.acknowledgements)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// A licence's text exactly as published, small, one text per paragraph so each reads and wraps on its own.
private struct LicenceText: View {
    private let paragraphs: [String]

    init(_ text: String) {
        // Commit Mono's licence ships with Windows line endings.
        self.paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            ForEach(paragraphs.indices, id: \.self) { index in
                Text(verbatim: paragraphs[index])
                    .font(LarderFont.body(.footnote))
                    .foregroundStyle(LarderColor.ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Licence texts that ship as code because the library's own files are not in the app bundle.
nonisolated enum ThirdPartyLicence {
    /// GRDB.swift's LICENSE, unchanged.
    static let grdb = """
        Copyright (C) 2015-2025 Gwendal Roué

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated \
        documentation files (the "Software"), to deal in the Software without restriction, including without limitation \
        the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and \
        to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions \
        of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED \
        TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL \
        THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF \
        CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER \
        DEALINGS IN THE SOFTWARE.
        """
}

#if DEBUG
#Preview("Acknowledgements") {
    NavigationStack {
        AcknowledgementsView()
    }
}
#endif
