import SwiftUI

struct QuickAction: View {
    let label: String
    let icon: String
    let onTap: () -> Void
    var body: some View {
        AppCard(padding: 10, onTap: onTap) {
            VStack(spacing: 6) {
                IconBadge(icon: icon, tint: Brand.maroon, size: 40, circle: true)
                Text(label).font(T.labelMedium).foregroundColor(Brand.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct MenuRow: View {
    let title: String
    let sub: String
    let icon: String
    var tint: Color = Brand.navy
    let onTap: () -> Void
    var body: some View {
        AppCard(padding: 14, onTap: onTap) {
            HStack(spacing: 12) {
                IconBadge(icon: icon, tint: tint, size: 40, bgOpacity: 0.1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(T.titleSmall).foregroundColor(Brand.ink)
                    Text(sub).font(T.bodySmall).foregroundColor(Brand.muted).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundColor(Brand.muted)
            }
        }
    }
}

struct CircleCard: View {
    let c: StudyCircle
    let snap: CenterSnapshot
    let onTap: () -> Void
    var body: some View {
        let students = snap.studentsIn(c.id)
        let todayIso = Days.iso(Days.today)
        let att = snap.attendance.filter { $0.circleId == c.id && $0.day == todayIso }
        let present = att.filter { $0.status.isPresent }.count
        AppCard(padding: 14, onTap: onTap) {
            HStack(spacing: 12) {
                IconBadge(icon: "person.3.fill", tint: Brand.navy, size: 46, corner: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name).font(T.titleSmall).foregroundColor(Brand.ink)
                    Text(snap.member(c.teacherId)?.fullName ?? "بدون معلم").font(T.bodySmall).foregroundColor(Brand.muted)
                    if !c.schedule.isEmpty { Text(c.schedule).font(T.labelSmall).foregroundColor(Brand.muted) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Pill(text: "\(students.count) طالب", color: Brand.navy)
                    if !c.level.isEmpty { Pill(text: c.level, color: Brand.maroon) }
                }
            }
            if !att.isEmpty {
                Spacer().frame(height: 10)
                HStack(spacing: 8) {
                    Text("حضور اليوم \(present)/\(att.count)").font(T.labelSmall).foregroundColor(Brand.muted)
                    LinearMeter(progress: Double(present) / Double(att.count), color: Brand.green)
                }
            }
        }
    }
}

struct StudentRow<Trailing: View>: View {
    let s: Student
    let snap: CenterSnapshot
    let onTap: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        let stats = Stats.forStudent(s, snap)
        AppCard(padding: 12, onTap: onTap) {
            HStack(spacing: 12) {
                Avatar(name: s.fullName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.fullName).font(T.titleSmall).foregroundColor(Brand.ink)
                    Text((snap.circle(s.circleId)?.name ?? "بدون حلقة") + " • " + Fmt.one(stats.juzEquivalent) + " جزء")
                        .font(T.bodySmall).foregroundColor(Brand.muted).lineLimit(1)
                    LinearMeter(progress: stats.goalProgress, color: Brand.navy).padding(.top, 4)
                }
                Spacer().frame(width: 4)
                trailing()
            }
        }
    }
}

struct RecordRow: View {
    let r: Recitation
    let snap: CenterSnapshot
    let showStudent: Bool
    var onDelete: (() -> Void)? = nil
    @EnvironmentObject var dialogs: DialogHost
    var body: some View {
        AppCard(padding: 12) {
            HStack(alignment: .center, spacing: 12) {
                IconBadge(icon: kindIcon(r.kind), tint: kindColor(r.kind), size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(showStudent ? (snap.student(r.studentId)?.fullName ?? "") : r.kind.label).font(T.titleSmall).foregroundColor(Brand.ink)
                    Text(Stats.describeRange(r) + " • \(Stats.ayatOf(r)) آية").font(T.bodySmall).foregroundColor(Brand.muted)
                    Text(Fmt.relative(r.recordedAt) + (r.mistakes > 0 ? " • \(r.mistakes) أخطاء" : "")).font(T.labelSmall).foregroundColor(Brand.muted)
                    if !r.notes.isEmpty { Text(r.notes).font(T.bodySmall).foregroundColor(Brand.ink) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Pill(text: r.grade.label, color: gradeColor(r.grade))
                    if showStudent { Pill(text: r.kind.short, color: kindColor(r.kind)) }
                    if let onDelete = onDelete {
                        Button {
                            dialogs.show(ConfirmDialog(title: "حذف السجل؟", message: "سيُحذف هذا السجل وتتحدث الإحصائيات.", confirm: "حذف", destructive: true, onConfirm: onDelete))
                        } label: {
                            Image(systemName: "trash").font(.system(size: 15)).foregroundColor(Brand.muted).frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("حذف")
                    }
                }
            }
        }
    }
}
