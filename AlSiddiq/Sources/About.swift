import SwiftUI
import UIKit

// v3.4 «عن المركز». Public (no password). Server (MIGRATIONS_v3.md 'v3.4'): table centre_about (center_id, body,
// photos jsonb = ordered paths in the public bucket 'center-about', updated_at sent by the client), table
// centre_about_buttons (label, kind call|whatsapp|link|email|map, value, sort). Admin writes only.
// «تواصل مع المطوّر» is his own package (Contact / ContactDeveloperView), fixed in the app, not editable.
// No row yet = his bundled text and photo are shown. The last fetched version is cached for offline.

struct AboutButton: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var label: String
    var kind: String      // call | whatsapp | link | email | map
    var value: String
    var sort: Int = 0

    static let kinds: [(String, String, String)] = [   // kind, Arabic, icon
        ("call", "اتصال", "phone.fill"), ("whatsapp", "واتساب", "message.fill"), ("link", "رابط", "link"),
        ("email", "بريد", "envelope.fill"), ("map", "خريطة", "map.fill")
    ]
    var icon: String { Self.kinds.first { $0.0 == kind }?.2 ?? "link" }
    var kindName: String { Self.kinds.first { $0.0 == kind }?.1 ?? kind }

    var url: URL? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = Passwords.normalise(v).filter { $0.isNumber || $0 == "+" }
        switch kind {
        case "call": return URL(string: "tel:" + digits)
        case "whatsapp": return URL(string: "https://wa.me/" + digits.replacingOccurrences(of: "+", with: ""))
        case "email": return URL(string: "mailto:" + v)
        case "map":
            if v.hasPrefix("http") { return URL(string: v) }
            return URL(string: "https://maps.apple.com/?q=" + (v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
        default: return URL(string: v.hasPrefix("http") ? v : "https://" + v)
        }
    }
}

struct AboutInfo: Codable, Equatable {
    var body: String
    /// Storage paths in the 'center-about' bucket (empty + fromServer=false = the bundled photo).
    var photos: [String] = []
    var buttons: [AboutButton] = []
    var fromServer = false
    var updatedAt: Date? = nil
    /// v3.9: the admin's «تواصل مع المركز» switch (optional so an older cache still decodes; nil = off).
    var contactButton: Bool? = nil
    /// v3.9: the number «تواصل مع المركز» dials (typed by the admin; "" or nil = the button opens «عن المركز»).
    var contactPhone: String? = nil

    static var bundledText: String {
        guard let u = Bundle.main.url(forResource: "about_text_ar", withExtension: "txt"), let s = try? String(contentsOf: u, encoding: .utf8) else { return "" }
        return s
    }
    static var bundledPhoto: UIImage? {
        Bundle.main.path(forResource: "about_photo_1", ofType: "jpg").flatMap { UIImage(contentsOfFile: $0) }
    }
    static var fallback: AboutInfo { AboutInfo(body: bundledText) }

    /// The text before «العنوان:», and the address after it (shown as its own card). Nothing is rewritten.
    var split: (String, String?) {
        guard let r = body.range(of: "العنوان:") else { return (body.trimmingCharacters(in: .whitespacesAndNewlines), nil) }
        let main = String(body[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let addr = String(body[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (main, addr.isEmpty ? nil : addr)
    }
}

struct AboutCenterScreen: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var dialogs: DialogHost
    @State private var info = AboutInfo.fallback
    @State private var images: [String: UIImage] = [:]
    @State private var page = 0
    @State private var editing = false
    @State private var picking = false
    @State private var busy = false
    private var isAdmin: Bool { model.user?.role == .admin }

    var body: some View {
        let (main, addr) = info.split
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                gallery
                if isAdmin { adminPhotoBar }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image("Logo").resizable().scaledToFit().frame(width: 40, height: 40)
                        Text(model.centerName.isEmpty ? "مركز الصديق لتعليم القرآن الكريم" : model.centerName)
                            .font(T.titleMedium).foregroundColor(Brand.ink)
                    }
                    Rectangle().fill(Brand.gold).frame(width: 44, height: 3).cornerRadius(2)
                    Text(main).font(AppFont.f(16)).lineSpacing(7).foregroundColor(Brand.ink)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("aboutText")
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Brand.card))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Brand.gold.opacity(0.35), lineWidth: 1))
                if let a = addr {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 22, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.maroon))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("العنوان").font(T.titleSmall).foregroundColor(Brand.ink)
                            Text(a).font(T.bodyMedium).foregroundColor(Brand.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Brand.card))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Brand.line, lineWidth: 1))
                    .accessibilityIdentifier("aboutAddress")
                }
                if !info.buttons.isEmpty || isAdmin { buttonsCard }
                if isAdmin {
                    OutlineButton(title: "تعديل النص", icon: "square.and.pencil") { editing = true }
                }
            }
            .padding(18)
        }
        .background(Brand.bg.ignoresSafeArea())
        .appNavTitle("عن المركز")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $editing) {
            AboutTextEditor(initial: info.body) { text in
                Task { busy = true; defer { busy = false }
                    do { try await model.repo.saveAboutText(text); await load(); model.say("تم الحفظ") }
                    catch { model.say((error as? LocalizedError)?.errorDescription ?? "تعذّر الحفظ") }
                }
            }
        }
        .sheet(isPresented: $picking) {
            PhotoPickerSheet(source: .library) { img in
                picking = false
                guard let img = img, let data = PhotoTools.jpeg(img, maxSide: 1280) else { return }
                Task { busy = true; defer { busy = false }
                    do { try await model.repo.addAboutPhoto(data); await load(); model.say("أُضيفت الصورة") }
                    catch { model.say((error as? LocalizedError)?.errorDescription ?? "تعذّر رفع الصورة") }
                }
            }
        }
    }

    private func load() async {
        info = model.repo.aboutCenter
        await refreshImages()
        await model.repo.refreshAbout()
        info = model.repo.aboutCenter
        await refreshImages()
    }

    private func refreshImages() async {
        for p in info.photos where images[p] == nil {
            if let i = await model.repo.aboutPhoto(p) { images[p] = i }
        }
    }

    private var shownPhotos: [(String, UIImage)] {
        // no photo on the server yet: his bundled photo (the admin's first added photo keeps it, see addAboutPhoto)
        if info.photos.isEmpty, let b = AboutInfo.bundledPhoto { return [("bundled", b)] }
        return info.photos.compactMap { p in images[p].map { (p, $0) } }
    }

    @ViewBuilder private var gallery: some View {
        let ph = shownPhotos
        if !ph.isEmpty {
            TabView(selection: $page) {
                ForEach(Array(ph.enumerated()), id: \.offset) { i, item in
                    Image(uiImage: item.1).resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 240).clipped()
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: ph.count > 1 ? .always : .never))
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Brand.gold.opacity(0.5), lineWidth: 1))
            .accessibilityIdentifier("aboutGallery")
        }
    }

    private var adminPhotoBar: some View {
        let ph = shownPhotos
        return HStack(spacing: 10) {
            OutlineButton(title: busy ? "جارٍ…" : "إضافة صورة", icon: "photo.badge.plus") { picking = true }
            if ph.indices.contains(page), ph[page].0 != "bundled" {
                let path = ph[page].0
                OutlineButton(title: "حذف هذه الصورة", icon: "trash") {
                    dialogs.show(ConfirmDialog(title: "حذف الصورة؟", message: "تُحذف من صفحة «عن المركز» عند الجميع.", confirm: "حذف", destructive: true) {
                        Task { do { try await model.repo.removeAboutPhoto(path); images[path] = nil; page = 0; await load() }
                               catch { model.say((error as? LocalizedError)?.errorDescription ?? "تعذّر الحذف") } }
                    })
                }
            }
        }
    }

    private var buttonsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isAdmin {
                HStack {
                    Text("أزرار التواصل").font(T.titleSmall).foregroundColor(Brand.ink)
                    Spacer()
                    Button { dialogs.show(AboutButtonDialog(button: nil, nextSort: (info.buttons.map { $0.sort }.max() ?? 0) + 1)) } label: {
                        Label("زر جديد", systemImage: "plus.circle.fill").font(T.labelLarge).foregroundColor(Brand.navy)
                    }
                    .accessibilityIdentifier("aboutAddButton")
                }
            }
            if info.buttons.isEmpty && isAdmin {
                Text("لا توجد أزرار بعد. أضف زر اتصال أو واتساب أو رابط أو بريد أو خريطة.").font(T.bodySmall).foregroundColor(Brand.muted)
            }
            ForEach(Array(info.buttons.sorted { $0.sort < $1.sort }.enumerated()), id: \.element.id) { i, b in
                HStack(spacing: 8) {
                    Button { if let u = b.url { UIApplication.shared.open(u) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: b.icon).foregroundColor(.white).frame(width: 36, height: 36)
                                .background(SwiftUI.Circle().fill(Brand.navy))
                            Text(b.label).font(T.titleSmall).foregroundColor(Brand.ink)
                            Spacer()
                            Image(systemName: "chevron.backward").foregroundColor(Brand.gold)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.card))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Brand.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    if isAdmin {
                        VStack(spacing: 2) {
                            Button { Task { try? await model.repo.moveAboutButton(b.id, up: true); await load() } } label: { Image(systemName: "chevron.up") }
                                .disabled(i == 0)
                            Button { Task { try? await model.repo.moveAboutButton(b.id, up: false); await load() } } label: { Image(systemName: "chevron.down") }
                                .disabled(i == info.buttons.count - 1)
                        }
                        .foregroundColor(Brand.navy).frame(width: 28)
                        Button { dialogs.show(AboutButtonDialog(button: b, nextSort: b.sort)) } label: { Image(systemName: "pencil").foregroundColor(Brand.navy).frame(width: 30, height: 30) }
                        Button {
                            dialogs.show(ConfirmDialog(title: "حذف «\(b.label)»؟", message: "يُحذف الزر عند الجميع.", confirm: "حذف", destructive: true) {
                                Task { try? await model.repo.deleteAboutButton(b.id); await load() }
                            })
                        } label: { Image(systemName: "trash").foregroundColor(Brand.red).frame(width: 30, height: 30) }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Brand.goldSoft.opacity(0.5)))
    }
}

private struct AboutTextEditor: View {
    let initial: String
    let onSave: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TextEditor(text: $text).font(AppFont.f(16)).padding(12)
                .background(Brand.bg.ignoresSafeArea())
                .appNavTitle("نص «عن المركز»").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("حفظ") { onSave(text); dismiss() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { if text.isEmpty { text = initial } }
    }
}

struct AboutButtonDialog: View {
    let button: AboutButton?
    let nextSort: Int
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var dialogs: DialogHost
    @State private var label = ""
    @State private var kind = "call"
    @State private var value = ""
    @State private var loaded = false
    var body: some View {
        DialogCard(title: button == nil ? "زر جديد" : "تعديل الزر") {
            VStack(alignment: .leading, spacing: 10) {
                Field(label: "اسم الزر (مثال: اتصل بالإدارة)", text: $label)
                ChoiceChips(options: AboutButton.kinds.map { $0.1 }, selected: AboutButton.kinds.firstIndex { $0.0 == kind } ?? 0) { kind = AboutButton.kinds[$0].0 }
                Field(label: kind == "call" || kind == "whatsapp" ? "الرقم" : (kind == "email" ? "البريد" : (kind == "map" ? "العنوان أو رابط الخريطة" : "الرابط")), text: $value)
            }
        } buttons: {
            DialogButton(title: "إلغاء") { dialogs.dismiss() }
            DialogButton(title: "حفظ", filled: true, enabled: !label.trimmingCharacters(in: .whitespaces).isEmpty && !value.trimmingCharacters(in: .whitespaces).isEmpty) {
                let b = AboutButton(id: button?.id ?? "", label: label.trimmingCharacters(in: .whitespaces), kind: kind,
                                    value: value.trimmingCharacters(in: .whitespaces), sort: button?.sort ?? nextSort)
                model.run("تم الحفظ", { try await model.repo.saveAboutButton(b) }) { _ in dialogs.dismiss() }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let b = button { label = b.label; kind = b.kind; value = b.value }
        }
    }
}
