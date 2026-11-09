import SwiftUI
import UIKit

// MARK: - v3.9 (Nov 9 2026): Friday is a rest day; «حضور و انصراف» per teacher; teachers' مستأذن; «تواصل مع المركز».

/// Friday is a rest day: nothing is recorded on a Friday (students' attendance, teachers' sheet, «تسجيل تسميع»).
/// Records run Saturday to Thursday, each with its date. Gregorian weekday: 1 Sunday … 6 Friday, 7 Saturday.
enum RestDay {
    static func isRest(_ d: Date) -> Bool { Days.cal.component(.weekday, from: d) == 6 }
    /// The nearest record day on or before d (a Friday goes back to Thursday).
    static func lastWorkDayOnOrBefore(_ d: Date) -> Date {
        var x = Days.dayOf(d)
        while isRest(x) { x = Days.add(x, -1) }
        return x
    }
    /// The previous record day before d (skips Friday).
    static func prevWorkDay(_ d: Date) -> Date {
        var x = Days.add(d, -1)
        while isRest(x) { x = Days.add(x, -1) }
        return x
    }
    /// The next record day after d, never later than today (skips Friday). nil when there is none yet.
    static func nextWorkDay(_ d: Date, today: Date = Days.today) -> Date? {
        var x = Days.add(d, 1)
        while isRest(x) { x = Days.add(x, 1) }
        return x > today ? nil : x
    }
    static let message = "الجمعة يوم راحة، ما يُسجَّل فيه شي. السجل من السبت إلى الخميس."
}

/// The card «اليوم الجمعة — يوم راحة» shown on a Friday.
struct RestDayCard: View {
    var body: some View {
        AppCard(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("اليوم الجمعة — يوم راحة").font(T.titleSmall).foregroundColor(Brand.ink)
                Text(RestDay.message).font(T.bodySmall).foregroundColor(Brand.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "HH:mm" helpers for the check-in / check-out times (the server returns "HH:mm:ss").
enum HM {
    static func clean(_ s: String?) -> String? {
        guard let s = s, s.count >= 5 else { return nil }
        return String(s.prefix(5))
    }
    static func parts(_ s: String?) -> (Int, Int)? {
        guard let c = clean(s) else { return nil }
        let p = c.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return (h, m)
    }
}

/// A time chip «حضور 07:45» / «انصراف —» on a teacher's row; opens the time sheet.
struct TeacherTimeChip: View {
    let label: String
    let value: String?
    let enabled: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(value.map { "\(label) \($0)" } ?? "\(label) —")
                .font(T.labelLarge)
                .foregroundColor(enabled ? Brand.navy : Brand.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(value != nil ? Brand.navy.opacity(0.14) : Brand.navy.opacity(0.05)))
        }
        .disabled(!enabled)
    }
}

/// The time sheet: hour and minute wheels (24 h), «تم» to keep, «مسح» to clear.
struct TeacherTimeSheet: View {
    let title: String
    let initial: String?
    let onSave: (String) -> Void
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hour: Int
    @State private var minute: Int

    init(title: String, initial: String?, onSave: @escaping (String) -> Void, onClear: @escaping () -> Void) {
        self.title = title
        self.initial = initial
        self.onSave = onSave
        self.onClear = onClear
        let p = HM.parts(initial) ?? (8, 0)
        _hour = State(initialValue: p.0)
        _minute = State(initialValue: p.1)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(T.titleSmall).foregroundColor(Brand.ink)
            HStack(spacing: 0) {
                Picker("الساعة", selection: $hour) {
                    ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d", h)).tag(h) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                Text(":").font(T.titleLarge).foregroundColor(Brand.ink)
                Picker("الدقيقة", selection: $minute) {
                    ForEach(0..<60, id: \.self) { m in Text(String(format: "%02d", m)).tag(m) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 180)
            HStack(spacing: 10) {
                Button { onClear(); dismiss() } label: {
                    Text("مسح").font(T.labelLarge).foregroundColor(Brand.red).frame(maxWidth: .infinity).frame(height: 44)
                }
                Button { dismiss() } label: {
                    Text("إلغاء").font(T.labelLarge).foregroundColor(Brand.ink).frame(maxWidth: .infinity).frame(height: 44)
                }
                Button { onSave(String(format: "%02d:%02d", hour, minute)); dismiss() } label: {
                    Text("تم").font(T.labelLarge).foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.navy))
                }
            }
        }
        .padding(20)
        .presentationDetents([.height(340)])
    }
}

/// «تواصل مع المركز»: the number the button dials (digits and a leading +; Arabic digits read as Latin).
/// No number = the button opens «عن المركز».
enum Dial {
    static func digits(_ phone: String) -> String {
        var out = ""
        for (i, c) in phone.trimmingCharacters(in: .whitespacesAndNewlines).enumerated() {
            if c.isNumber, let v = c.wholeNumberValue { out += String(v) }
            else if i == 0 && c == "+" { out += "+" }
        }
        return out
    }
}

/// Taps «تواصل مع المركز»: dial the admin's number, or open «عن المركز» when there is none.
@MainActor
enum ContactCentreTap {
    static func run(phone: String, tools: ToolsHost) {
        let d = Dial.digits(phone)
        if !d.isEmpty, let url = URL(string: "tel:" + d) { UIApplication.shared.open(url) }
        else { tools.show(.about) }
    }
}

/// The admin's switch «تواصل مع المركز» on the «الإدارة» page (default off), with the number it dials.
struct ContactCentreSwitch: View {
    @EnvironmentObject var model: AppModel
    @State private var on = false
    @State private var number = ""
    var body: some View {
        AppCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("تواصل مع المركز").font(T.titleSmall).foregroundColor(Brand.ink)
                        Text("زر يظهر للجميع في الصفحة الرئيسية، ويتصل بالرقم اللي تكتبه — اختياري").font(T.bodySmall).foregroundColor(Brand.muted)
                    }
                    Spacer(minLength: 8)
                    Toggle("تواصل مع المركز", isOn: Binding(get: { on }, set: { v in
                        on = v
                        save(v, number)
                    }))
                    .labelsHidden()
                    .tint(Brand.navy)
                    .accessibilityIdentifier("contactCentreSwitch")
                }
                TextField("رقم التواصل", text: $number)
                    .keyboardType(.phonePad)
                    .font(T.bodyMedium)
                    .foregroundColor(Brand.ink)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.line, lineWidth: 1.2))
                    .accessibilityIdentifier("contactPhoneField")
                Button { save(on, number) } label: {
                    Text("حفظ الرقم").font(T.labelLarge).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.navy))
                }
                .disabled(number.trimmingCharacters(in: .whitespacesAndNewlines) == (model.repo.aboutCenter.contactPhone ?? ""))
                .accessibilityIdentifier("saveContactPhone")
            }
        }
        .onAppear {
            let a = model.repo.aboutCenter
            on = a.contactButton == true
            number = a.contactPhone ?? ""
        }
    }

    private func save(_ v: Bool, _ n: String) {
        let p = n.trimmingCharacters(in: .whitespacesAndNewlines)
        model.run("تم حفظ «تواصل مع المركز»", { try await model.repo.saveContactButton(v, phone: p) },
                  onError: { on = model.repo.aboutCenter.contactButton == true }, then: { _ in number = p })
    }
}

/// «تواصل مع المركز» on the opening (password) screen, under «عن المركز» / «المطور»: only when the admin switched it on.
struct OpeningContactButton: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tools: ToolsHost
    @State private var on = false
    @State private var phone = ""
    var body: some View {
        // a VStack, not a Group: a Group that renders nothing does not run its .task
        VStack(spacing: 0) {
            if on {
                Button { ContactCentreTap.run(phone: phone, tools: tools) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "phone.fill").font(.system(size: 13, weight: .bold))
                        Text("تواصل مع المركز").font(T.labelLarge)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .overlay(Capsule().stroke(Brand.gold.opacity(0.7), lineWidth: 1))
                }
                .accessibilityIdentifier("contactCentreButton")
            }
        }
        .task {
            // the switch and its number are public (anon key), read before any password
            await model.repo.refreshAbout()
            let a = model.repo.aboutCenter
            on = a.contactButton == true
            phone = a.contactPhone ?? ""
        }
    }
}

/// «تواصل مع المركز» in the general Settings, under «عن المركز» (when the admin switched it on).
struct ContactCentreMenuRow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tools: ToolsHost
    @State private var on = false
    @State private var phone = ""
    var body: some View {
        VStack(spacing: 0) {
            if on {
                MenuRow(title: "تواصل مع المركز", sub: "اتصال بالمركز", icon: "phone.fill", tint: Brand.green) {
                    ContactCentreTap.run(phone: phone, tools: tools)
                }
            }
        }
        .task {
            await model.repo.refreshAbout()
            let a = model.repo.aboutCenter
            on = a.contactButton == true
            phone = a.contactPhone ?? ""
        }
    }
}
