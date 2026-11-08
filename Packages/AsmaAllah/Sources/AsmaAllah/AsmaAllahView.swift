import SwiftUI

final class AsmModel: ObservableObject {
    @Published var query = ""
    @Published var open: Int? = nil
    private let keys: [Int: String] = Dictionary(uniqueKeysWithValues: AsmaData.names.map { ($0.n, AsmaData.key($0.plain + " " + $0.meaning)) })

    var results: [AsmName] {
        let q = AsmaData.key(query.trimmingCharacters(in: .whitespacesAndNewlines))
        if q.isEmpty { return AsmaData.names }
        if let num = Int(q.filter { $0.isNumber }), q.allSatisfy({ $0.isNumber }) {
            return AsmaData.names.filter { $0.n == num }
        }
        return AsmaData.names.filter { keys[$0.n]?.contains(q) == true }
    }
}

/// «أسماء الله الحسنى» — the button's single entry view.
public struct AsmaAllahView: View {
    @StateObject private var m = AsmModel()

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                searchField
                let list = m.results
                if list.isEmpty {
                    Text(verbatim: "ما فيه نتائج")
                        .foregroundColor(.secondary)
                        .padding(.top, 30)
                }
                ForEach(list) { x in row(x) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AsmTheme.bg.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "أسماء الله الحسنى"))
        .navigationBarTitleDisplayMode(.inline)
        .tint(AsmTheme.accent)
        .asmRTL()
    }

    private var header: some View {
        AsmCard {
            VStack(spacing: 8) {
                Text(verbatim: "قال النبي ﷺ: «\(AsmaData.hadith)»")
                    .font(.system(size: 17, weight: .medium))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: AsmaData.hadithRef).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField(text: $m.query) { Text(verbatim: "ابحث بالاسم أو المعنى أو الرقم") }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !m.query.isEmpty {
                Button { m.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AsmTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AsmTheme.line, lineWidth: 0.5))
    }

    private func row(_ x: AsmName) -> some View {
        AsmCard {
            HStack(alignment: .top, spacing: 14) {
                Text(verbatim: "\(x.n)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AsmTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AsmTheme.soft))
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: x.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.primary)
                    Text(verbatim: x.meaning)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .textSelection(.enabled)
    }
}
