//
//  DayPlannerApp.swift
//  Распорядок дня + To-Do  (v1.2, MVP)
//
//  Требования: Xcode 26+, iOS 26.0+ (Liquid Glass).
//  Для Напоминаний в Info.plist нужен ключ NSRemindersFullAccessUsageDescription
//  (он уже добавлен в build-ipa.yml).
//

import SwiftUI
import EventKit

// MARK: - Приложение

@main
struct DayPlannerApp: App {
    @StateObject private var store = Store()
    @AppStorage("theme") private var theme = 0
    @AppStorage("accent") private var accent = 0

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .environment(\.calendar, Calendar.planner)
                .environment(\.brand, Palette.color(accent))
                .tint(Palette.color(accent))
                .preferredColorScheme(Palette.scheme(theme))
        }
    }
}

// MARK: - Тема и акцентный цвет

enum Palette {
    static let colors: [Color] = [.blue, .indigo, .purple, .pink, .orange, .green, .teal]

    static func color(_ i: Int) -> Color {
        colors.indices.contains(i) ? colors[i] : Color.blue
    }

    static func scheme(_ t: Int) -> ColorScheme? {
        switch t {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}

private struct BrandKey: EnvironmentKey {
    static let defaultValue: Color = .blue
}

extension EnvironmentValues {
    var brand: Color {
        get { self[BrandKey.self] }
        set { self[BrandKey.self] = newValue }
    }
}

// MARK: - Календарь и форматирование

extension Calendar {
    /// Григорианский календарь, неделя начинается с понедельника
    static let planner: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()
}

private let cal = Calendar.planner

/// Порядок дней недели (Calendar.weekday: 1 = Вс, 2 = Пн ... 7 = Сб)
let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

func shortWeekday(_ wd: Int) -> String {
    ["", "Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"][wd]
}

func durationText(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h == 0 { return "\(m) мин" }
    if m == 0 { return "\(h) ч" }
    return "\(h) ч \(m) мин"
}

enum Fmt {
    static func string(_ date: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.calendar = cal
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    static func time(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

extension String {
    var capFirst: String { prefix(1).uppercased() + String(dropFirst()) }
}

extension Date {
    var startOfDay: Date { cal.startOfDay(for: self) }
    var weekday: Int { cal.component(.weekday, from: self) }

    func addingDays(_ n: Int) -> Date {
        cal.date(byAdding: .day, value: n, to: self) ?? self
    }

    /// Понедельник недели, в которую входит дата
    var weekStart: Date {
        cal.dateInterval(of: .weekOfYear, for: self)?.start ?? startOfDay
    }

    /// 7 дней недели (с понедельника)
    var weekDays: [Date] {
        let start = weekStart
        return (0..<7).map { start.addingDays($0) }
    }

    /// Минуты от полуночи
    var minutesOfDay: Int {
        let c = cal.dateComponents([.hour, .minute], from: self)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

// MARK: - Модели

enum RoutineKind: String, Codable, CaseIterable, Identifiable {
    case wake, meal, sport, work, free, sleep, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wake: "Подъём"
        case .meal: "Приём пищи"
        case .sport: "Спорт"
        case .work: "Работа"
        case .free: "Свободное время"
        case .sleep: "Отбой"
        case .other: "Другое"
        }
    }

    var icon: String {
        switch self {
        case .wake: "sunrise.fill"
        case .meal: "fork.knife"
        case .sport: "figure.run"
        case .work: "briefcase.fill"
        case .free: "gamecontroller.fill"
        case .sleep: "moon.zzz.fill"
        case .other: "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .wake: Color.orange
        case .meal: Color.green
        case .sport: Color.red
        case .work: Color.blue
        case .free: Color.purple
        case .sleep: Color.indigo
        case .other: Color.gray
        }
    }
}

/// Часть суток — для разделения распорядка
enum DayPart: CaseIterable, Identifiable {
    case morning, day, evening, night

    var id: String { title }

    static func of(_ minutes: Int) -> DayPart {
        let m = ((minutes % 1440) + 1440) % 1440
        switch m {
        case 240..<720: return .morning
        case 720..<1080: return .day
        case 1080..<1440: return .evening
        default: return .night
        }
    }

    var title: String {
        switch self {
        case .morning: "Утро"
        case .day: "День"
        case .evening: "Вечер"
        case .night: "Ночь"
        }
    }

    var range: String {
        switch self {
        case .morning: "04:00 – 12:00"
        case .day: "12:00 – 18:00"
        case .evening: "18:00 – 24:00"
        case .night: "00:00 – 04:00"
        }
    }

    var icon: String {
        switch self {
        case .morning: "sunrise.fill"
        case .day: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .morning: Color.orange
        case .day: Color.yellow
        case .evening: Color.pink
        case .night: Color.indigo
        }
    }
}

struct ScheduleItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var kind: RoutineKind
    var start: Int          // минуты от полуночи
    var duration: Int       // минуты (0 = без длительности)
    var weekdays: Set<Int>  // Calendar.weekday
    var reminderID: String?

    var end: Int { start + duration }
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var isDone = false
    var reminderID: String?
}

struct ReminderListInfo: Identifiable {
    let id: String
    let title: String
}

// MARK: - Интеграция с Напоминаниями (EventKit)

final class RemindersService {
    private let eventStore = EKEventStore()
    private let defaults = UserDefaults.standard

    var tasksOn: Bool { defaults.bool(forKey: "remTasks") }
    var routineOn: Bool { defaults.bool(forKey: "remRoutine") }
    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    func requestAccess() async -> Bool {
        if hasAccess { return true }
        return (try? await eventStore.requestFullAccessToReminders()) ?? false
    }

    func allLists() -> [EKCalendar] {
        guard hasAccess else { return [] }
        return eventStore.calendars(for: .reminder).filter { $0.allowsContentModifications }
    }

    /// Ищет список по сохранённому id или названию, иначе создаёт новый
    private func list(named title: String, idKey: String) -> EKCalendar? {
        if let id = defaults.string(forKey: idKey), !id.isEmpty,
           let found = eventStore.calendar(withIdentifier: id) {
            return found
        }
        if let found = eventStore.calendars(for: .reminder)
            .first(where: { $0.title == title && $0.allowsContentModifications }) {
            defaults.set(found.calendarIdentifier, forKey: idKey)
            return found
        }
        let created = EKCalendar(for: .reminder, eventStore: eventStore)
        created.title = title
        created.source = eventStore.defaultCalendarForNewReminders()?.source ?? eventStore.sources.first
        do {
            try eventStore.saveCalendar(created, commit: true)
            defaults.set(created.calendarIdentifier, forKey: idKey)
            return created
        } catch {
            return nil
        }
    }

    private var taskList: EKCalendar? { list(named: "Распорядок дня", idKey: "remListID") }
    private var routineList: EKCalendar? { list(named: "Расписание", idKey: "remRoutineListID") }

    func reminder(_ id: String?) -> EKReminder? {
        guard let id, let r = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return nil }
        return r
    }

    func date(of r: EKReminder) -> Date? {
        guard let comps = r.dueDateComponents, let d = cal.date(from: comps) else { return nil }
        return d.startOfDay
    }

    // Задачи

    func fetchTaskIDs() async -> [String] {
        guard tasksOn, hasAccess, let lst = taskList else { return [] }
        let predicate = eventStore.predicateForReminders(in: [lst])
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: (result ?? []).map { $0.calendarItemIdentifier })
            }
        }
    }

    func create(title: String, date: Date, done: Bool = false) -> String? {
        guard tasksOn, hasAccess, let lst = taskList else { return nil }
        let r = EKReminder(eventStore: eventStore)
        r.calendar = lst
        r.title = title
        r.isCompleted = done
        r.dueDateComponents = cal.dateComponents([.year, .month, .day], from: date)
        do {
            try eventStore.save(r, commit: true)
            return r.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    func update(id: String?, title: String? = nil, done: Bool? = nil, date: Date? = nil) {
        guard tasksOn, let r = reminder(id) else { return }
        if let title { r.title = title }
        if let done { r.isCompleted = done }
        if let date { r.dueDateComponents = cal.dateComponents([.year, .month, .day], from: date) }
        try? eventStore.save(r, commit: true)
    }

    func remove(id: String?) {
        guard tasksOn, let r = reminder(id) else { return }
        try? eventStore.remove(r, commit: true)
    }

    // Распорядок: повторяющиеся напоминания с сигналом в момент начала

    func syncRoutine(_ item: ScheduleItem) -> String? {
        guard routineOn, hasAccess, let lst = routineList else { return nil }
        let r = reminder(item.reminderID) ?? EKReminder(eventStore: eventStore)
        r.calendar = lst
        r.title = item.title
        r.notes = item.kind.title + (item.duration > 0 ? " · " + durationText(item.duration) : "")
        r.dueDateComponents = firstDue(for: item)

        r.recurrenceRules?.forEach { r.removeRecurrenceRule($0) }
        let days = item.weekdays.sorted()
            .compactMap { EKWeekday(rawValue: $0) }
            .map { EKRecurrenceDayOfWeek($0) }
        r.addRecurrenceRule(EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days,
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
            daysOfTheYear: nil, setPositions: nil, end: nil
        ))

        r.alarms?.forEach { r.removeAlarm($0) }
        r.addAlarm(EKAlarm(relativeOffset: 0))

        do {
            try eventStore.save(r, commit: true)
            return r.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    func removeRoutine(_ item: ScheduleItem) {
        guard let r = reminder(item.reminderID) else { return }
        try? eventStore.remove(r, commit: true)
    }

    private func firstDue(for item: ScheduleItem) -> DateComponents {
        let now = Date()
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        for i in 0..<8 {
            let day = now.startOfDay.addingDays(i)
            guard item.weekdays.contains(day.weekday),
                  let t = cal.date(bySettingHour: (item.start / 60) % 24, minute: item.start % 60, second: 0, of: day),
                  t > now else { continue }
            return cal.dateComponents(parts, from: t)
        }
        return cal.dateComponents(parts, from: now)
    }
}

// MARK: - Хранилище (JSON в Documents)

@MainActor
final class Store: ObservableObject {
    @Published private(set) var schedule: [ScheduleItem] = []
    @Published private(set) var todos: [TodoItem] = []

    let reminders = RemindersService()

    private struct Snapshot: Codable {
        var schedule: [ScheduleItem]
        var todos: [TodoItem]
    }

    private let url = URL.documentsDirectory.appending(path: "planner.json")

    init() {
        if let data = try? Data(contentsOf: url),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            schedule = snap.schedule
            todos = snap.todos
        } else {
            schedule = Self.sample()
            save()
        }
    }

    // Распорядок

    func items(forWeekday wd: Int) -> [ScheduleItem] {
        schedule.filter { $0.weekdays.contains(wd) }.sorted { $0.start < $1.start }
    }

    func upsert(_ item: ScheduleItem) {
        var item = item
        item.reminderID = reminders.syncRoutine(item)
        if let i = schedule.firstIndex(where: { $0.id == item.id }) {
            schedule[i] = item
        } else {
            schedule.append(item)
        }
        save()
    }

    /// Убирает пункт только из выбранного дня недели
    func remove(_ item: ScheduleItem, fromWeekday wd: Int) {
        guard let i = schedule.firstIndex(where: { $0.id == item.id }) else { return }
        schedule[i].weekdays.remove(wd)
        if schedule[i].weekdays.isEmpty {
            reminders.removeRoutine(schedule[i])
            schedule.remove(at: i)
        } else {
            schedule[i].reminderID = reminders.syncRoutine(schedule[i])
        }
        save()
    }

    func removeEverywhere(_ item: ScheduleItem) {
        reminders.removeRoutine(item)
        schedule.removeAll { $0.id == item.id }
        save()
    }

    // To-Do (невыполненные сверху, выполненные внизу)

    func todos(on date: Date) -> [TodoItem] {
        let all = todos.filter { cal.isDate($0.date, inSameDayAs: date) }
        return all.filter { !$0.isDone } + all.filter { $0.isDone }
    }

    func addTodo(_ title: String, on date: Date) {
        let day = date.startOfDay
        let rid = reminders.create(title: title, date: day)
        todos.append(TodoItem(title: title, date: day, reminderID: rid))
        save()
    }

    func updateTodo(_ todo: TodoItem, title: String, date: Date) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].title = title
        todos[i].date = date.startOfDay
        reminders.update(id: todos[i].reminderID, title: title, date: todos[i].date)
        save()
    }

    func toggle(_ todo: TodoItem) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].isDone.toggle()
        reminders.update(id: todos[i].reminderID, done: todos[i].isDone)
        save()
    }

    func delete(_ todo: TodoItem) {
        reminders.remove(id: todo.reminderID)
        todos.removeAll { $0.id == todo.id }
        save()
    }

    func clearCompleted() {
        for t in todos where t.isDone { reminders.remove(id: t.reminderID) }
        todos.removeAll { $0.isDone }
        save()
    }

    func resetAll() {
        for t in todos { reminders.remove(id: t.reminderID) }
        for s in schedule { reminders.removeRoutine(s) }
        todos = []
        schedule = Self.sample()
        for i in schedule.indices { schedule[i].reminderID = reminders.syncRoutine(schedule[i]) }
        save()
    }

    // Синхронизация с Напоминаниями

    func enableTaskSync() async -> Bool {
        guard await reminders.requestAccess() else { return false }
        for i in todos.indices where todos[i].reminderID == nil {
            todos[i].reminderID = reminders.create(
                title: todos[i].title, date: todos[i].date, done: todos[i].isDone
            )
        }
        save()
        await pullReminders()
        return true
    }

    func enableRoutineSync() async -> Bool {
        guard await reminders.requestAccess() else { return false }
        for i in schedule.indices { schedule[i].reminderID = reminders.syncRoutine(schedule[i]) }
        save()
        return true
    }

    func disableRoutineSync() {
        for i in schedule.indices {
            reminders.removeRoutine(schedule[i])
            schedule[i].reminderID = nil
        }
        save()
    }

    /// Подтягивает изменения из Напоминаний (новые, изменённые, удалённые задачи)
    func pullReminders() async {
        guard reminders.tasksOn, reminders.hasAccess else { return }
        let ids = await reminders.fetchTaskIDs()

        var list = todos
        var changed = false

        for id in ids where !list.contains(where: { $0.reminderID == id }) {
            guard let r = reminders.reminder(id) else { continue }
            list.append(TodoItem(
                title: r.title ?? "",
                date: reminders.date(of: r) ?? Date().startOfDay,
                isDone: r.isCompleted,
                reminderID: id
            ))
            changed = true
        }

        var i = 0
        while i < list.count {
            guard let id = list[i].reminderID else { i += 1; continue }
            if let r = reminders.reminder(id), r.refresh() {
                let title = r.title ?? list[i].title
                let day = reminders.date(of: r) ?? list[i].date
                if list[i].title != title
                    || list[i].isDone != r.isCompleted
                    || !cal.isDate(list[i].date, inSameDayAs: day) {
                    list[i].title = title
                    list[i].isDone = r.isCompleted
                    list[i].date = day
                    changed = true
                }
                i += 1
            } else {
                list.remove(at: i)   // удалено в Напоминаниях
                changed = true
            }
        }

        if changed {
            todos = list
            save()
        }
    }

    // Сохранение

    private func save() {
        let snap = Snapshot(schedule: schedule, todos: todos)
        do {
            try JSONEncoder().encode(snap).write(to: url, options: .atomic)
        } catch {
            print("Save error:", error)
        }
    }

    private static func sample() -> [ScheduleItem] {
        let all = Set(1...7)
        let work: Set<Int> = [2, 3, 4, 5, 6]
        return [
            ScheduleItem(title: "Подъём", kind: .wake, start: 7 * 60, duration: 0, weekdays: all),
            ScheduleItem(title: "Завтрак", kind: .meal, start: 7 * 60 + 30, duration: 30, weekdays: all),
            ScheduleItem(title: "Работа", kind: .work, start: 9 * 60, duration: 240, weekdays: work),
            ScheduleItem(title: "Обед", kind: .meal, start: 13 * 60, duration: 45, weekdays: all),
            ScheduleItem(title: "Работа", kind: .work, start: 14 * 60, duration: 240, weekdays: work),
            ScheduleItem(title: "Спорт", kind: .sport, start: 18 * 60 + 30, duration: 60, weekdays: [2, 4, 6]),
            ScheduleItem(title: "Свободное время", kind: .free, start: 20 * 60, duration: 90, weekdays: all),
            ScheduleItem(title: "Отбой", kind: .sleep, start: 23 * 60, duration: 0, weekdays: all)
        ]
    }
}

// MARK: - Свайп между вкладками
//
// Свой «пейджер» вместо TabView(.page): так горизонтальный свайп по строке задач
// остаётся системному swipeActions (удаление), а между вкладками листается
// по всему остальному экрану. Полоса недели листается сама.

struct PagerHandlers {
    var onDrag: (CGFloat) -> Void = { _ in }
    var onEnd: (CGFloat, CGFloat) -> Void = { _, _ in }
}

private struct PagerKey: EnvironmentKey {
    static let defaultValue = PagerHandlers()
}

extension EnvironmentValues {
    var pager: PagerHandlers {
        get { self[PagerKey.self] }
        set { self[PagerKey.self] = newValue }
    }
}

/// Вертикальная полоса экрана, занятая полосой недели
struct StripBandKey: PreferenceKey {
    static let defaultValue: ClosedRange<CGFloat>? = nil
    static func reduce(value: inout ClosedRange<CGFloat>?, nextValue: () -> ClosedRange<CGFloat>?) {
        value = nextValue() ?? value
    }
}

struct PagerSwipe: ViewModifier {
    let index: Int
    @Environment(\.pager) private var pager
    @State private var band: ClosedRange<CGFloat>?
    @State private var horizontal: Bool?
    @State private var ignored = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .coordinateSpace(.named("page"))
            .onPreferenceChange(StripBandKey.self) { band = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        if horizontal == nil {
                            horizontal = abs(v.translation.width) > abs(v.translation.height)
                            ignored = shouldIgnore(v)
                        }
                        if horizontal == true, !ignored {
                            pager.onDrag(v.translation.width)
                        }
                    }
                    .onEnded { v in
                        let active = horizontal == true && !ignored
                        horizontal = nil
                        ignored = false
                        if active {
                            pager.onEnd(v.translation.width, v.predictedEndTranslation.width)
                        }
                    }
            )
    }

    private func shouldIgnore(_ v: DragGesture.Value) -> Bool {
        // свайп по полосе недели — листает неделю, а не вкладки
        if let band, band.contains(v.startLocation.y) { return true }
        // на вкладке задач свайп влево — удаление строки
        if index == 2, v.translation.width < 0 { return true }
        return false
    }
}

extension View {
    func pagerSwipe(_ index: Int) -> some View {
        modifier(PagerSwipe(index: index))
    }
}

// MARK: - Корневой экран: 3 вкладки

struct RootView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var phase
    @State private var tab = 1   // по умолчанию — центральная
    @State private var dragX: CGFloat = 0
    @State private var width: CGFloat = 390

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 0) {
                    CalendarTab().frame(width: w)   // свайп вправо
                    ScheduleTab().frame(width: w)
                    TodoTab().frame(width: w)       // свайп влево
                }
                .frame(width: w * 3, height: geo.size.height, alignment: .leading)
                .offset(x: -CGFloat(tab) * w + dragX)
                .onAppear { width = w }
                .onChange(of: w) { _, new in width = new }
            }
            .clipped()
            .ignoresSafeArea(.container, edges: .bottom)

            GlassTabBar(selection: $tab)
        }
        .environment(\.pager, PagerHandlers(onDrag: drag, onEnd: settle))
        .sensoryFeedback(.selection, trigger: tab)
        .task { await store.pullReminders() }
        .onChange(of: phase) { _, new in
            if new == .active { Task { await store.pullReminders() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await store.pullReminders() }
        }
    }

    private func drag(_ dx: CGFloat) {
        let atEdge = (tab == 0 && dx > 0) || (tab == 2 && dx < 0)
        dragX = atEdge ? dx / 4 : dx
    }

    private func settle(_ dx: CGFloat, _ predicted: CGFloat) {
        var new = tab
        if dx < -width * 0.25 || predicted < -width * 0.5 {
            new = min(tab + 1, 2)
        } else if dx > width * 0.25 || predicted > width * 0.5 {
            new = max(tab - 1, 0)
        }
        withAnimation(.snappy) {
            tab = new
            dragX = 0
        }
    }
}

/// Нижний переключатель: стеклянная капсула с «таблеткой» выбранной вкладки
struct GlassTabBar: View {
    @Binding var selection: Int
    @Namespace private var ns
    @Environment(\.brand) private var brand

    private let items: [(title: String, icon: String)] = [
        ("Календарь", "calendar"),
        ("Распорядок", "clock"),
        ("Задачи", "checklist")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let selected = selection == i
                Button {
                    withAnimation(.snappy) { selection = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].icon)
                            .font(.system(size: 20, weight: .semibold))
                            .symbolVariant(selected ? .fill : .none)
                        Text(items[i].title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selected ? brand : Color.primary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selected {
                            Capsule()
                                .fill(brand.opacity(0.16))
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
}

// MARK: - Кнопка настроек

struct SettingsButton: View {
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            Label("Настройки", systemImage: "gearshape")
        }
        .sheet(isPresented: $show) { SettingsView() }
    }
}

// MARK: - Полоса недели с «липким» пролистыванием

struct WeekStrip: View {
    @Binding var date: Date
    @Environment(\.brand) private var brand
    @State private var weekIndex: Int?

    private static let base = Date().weekStart
    private static let range = -156...156   // ±3 года

    init(date: Binding<Date>) {
        _date = date
        _weekIndex = State(initialValue: Self.index(of: date.wrappedValue))
    }

    private static func index(of d: Date) -> Int {
        let days = cal.dateComponents([.day], from: base, to: d.weekStart).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    private static func start(of index: Int) -> Date {
        base.addingDays(index * 7)
    }

    var body: some View {
        let days = date.weekDays

        VStack(spacing: 10) {
            HStack {
                Button { shift(-7) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)

                Spacer()

                Text("\(Fmt.string(days[0], "d MMM")) – \(Fmt.string(days[6], "d MMM"))")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button { shift(7) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Self.range, id: \.self) { i in
                        weekRow(i)
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $weekIndex, anchor: .leading)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .padding(.vertical, 8)
        .background {
            GeometryReader { g in
                let f = g.frame(in: .named("page"))
                Color.clear.preference(key: StripBandKey.self, value: f.minY...f.maxY)
            }
        }
        .sensoryFeedback(.selection, trigger: weekIndex)
        .onChange(of: weekIndex) { _, new in
            // неделю пролистали — выбираем тот же день недели в новой неделе
            guard let new, new != Self.index(of: date) else { return }
            let offset = (date.weekday - cal.firstWeekday + 7) % 7
            date = Self.start(of: new).addingDays(offset)
        }
        .onChange(of: date) { _, new in
            // дату сменили (стрелки, «Сегодня») — докручиваем полосу до нужной недели
            let i = Self.index(of: new)
            if weekIndex != i {
                withAnimation(.snappy) { weekIndex = i }
            }
        }
    }

    private func weekRow(_ i: Int) -> some View {
        let start = Self.start(of: i)
        return GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { k in
                    chip(for: start.addingDays(k))
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func chip(for day: Date) -> some View {
        let selected = cal.isDate(day, inSameDayAs: date)
        let isToday = cal.isDateInToday(day)
        let glass: Glass = selected
            ? Glass.regular.tint(brand).interactive()
            : Glass.regular.interactive()

        return Button {
            withAnimation(.snappy) { date = day.startOfDay }
        } label: {
            VStack(spacing: 3) {
                Text(Fmt.string(day, "EEEEEE").capFirst)
                    .font(.caption2.weight(.semibold))
                Text("\(cal.component(.day, from: day))")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Circle()
                    .fill(isToday ? (selected ? Color.white : brand) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: .rect(cornerRadius: 18))
    }

    private func shift(_ days: Int) {
        withAnimation(.snappy) { date = date.addingDays(days) }
    }
}

// MARK: - Центральная вкладка: распорядок дня

struct EditorTarget: Identifiable {
    let id = UUID()
    var item: ScheduleItem?
    var weekday: Int
}

struct ScheduleTab: View {
    @EnvironmentObject private var store: Store
    @State private var date = Date().startOfDay
    @State private var editor: EditorTarget?
    @State private var now = Date()

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let items = store.items(forWeekday: date.weekday)
        let nowID = currentID(in: items)

        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(date: $date)

                List {
                    ForEach(DayPart.allCases) { part in
                        let rows = items.filter { DayPart.of($0.start) == part }
                        if !rows.isEmpty {
                            Section {
                                ForEach(rows) { item in
                                    Button {
                                        editor = EditorTarget(item: item, weekday: date.weekday)
                                    } label: {
                                        ScheduleRow(item: item, isNow: item.id == nowID)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            editor = EditorTarget(item: item, weekday: date.weekday)
                                        } label: {
                                            Label("Изменить", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            withAnimation { store.remove(item, fromWeekday: date.weekday) }
                                        } label: {
                                            Label("Убрать из этого дня", systemImage: "calendar.badge.minus")
                                        }
                                        Button(role: .destructive) {
                                            withAnimation { store.removeEverywhere(item) }
                                        } label: {
                                            Label("Удалить из всех дней", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                PartHeader(part: part)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .contentMargins(.bottom, 100, for: .scrollContent)
                .overlay {
                    if items.isEmpty {
                        ContentUnavailableView(
                            "Распорядок пуст",
                            systemImage: "clock",
                            description: Text("Нажмите «+», чтобы добавить пункт на этот день")
                        )
                    }
                }
            }
            .pagerSwipe(1)
            .navigationTitle(Fmt.string(date, "EEEE").capFirst)
            .navigationSubtitle(Fmt.string(date, "d MMMM"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    SettingsButton()
                    Button("Сегодня") {
                        withAnimation(.snappy) { date = Date().startOfDay }
                    }
                    .disabled(cal.isDateInToday(date))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = EditorTarget(item: nil, weekday: date.weekday)
                    } label: {
                        Label("Добавить", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $editor) { target in
            ScheduleEditor(item: target.item, weekday: target.weekday)
        }
        .onReceive(ticker) { now = $0 }
    }

    /// Какой пункт идёт «сейчас» (только для сегодняшнего дня)
    private func currentID(in items: [ScheduleItem]) -> UUID? {
        guard cal.isDateInToday(date) else { return nil }
        let m = now.minutesOfDay
        return items.last(where: { $0.start <= m })?.id
    }
}

struct PartHeader: View {
    let part: DayPart

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: part.icon)
                .foregroundStyle(part.color)
            Text(part.title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(part.range)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
    }
}

struct ScheduleRow: View {
    @Environment(\.brand) private var brand
    let item: ScheduleItem
    var isNow = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.time(item.start))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
                if item.duration > 0 {
                    Text(Fmt.time(item.end))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(minWidth: 50, alignment: .trailing)

            Image(systemName: item.kind.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(item.kind.color.gradient, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isNow {
                Text("Сейчас")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(brand.opacity(0.16), in: .capsule)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var subtitle: String? {
        if item.duration > 0 {
            return "\(item.kind.title) · \(durationText(item.duration))"
        }
        return item.title == item.kind.title ? nil : item.kind.title
    }
}

// MARK: - Добавление / редактирование пункта распорядка

struct ScheduleEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var brand
    @FocusState private var focused: Bool

    private let original: ScheduleItem?
    @State private var title: String
    @State private var kind: RoutineKind
    @State private var time: Date
    @State private var duration: Int
    @State private var weekdays: Set<Int>

    private static let durations = [0, 15, 30, 45, 60, 90, 120, 180, 240, 360, 480]

    init(item: ScheduleItem?, weekday: Int) {
        original = item
        _title = State(initialValue: item?.title ?? "")
        _kind = State(initialValue: item?.kind ?? .other)
        _time = State(initialValue: Self.date(fromMinutes: item?.start ?? 9 * 60))
        _duration = State(initialValue: item?.duration ?? 30)
        _weekdays = State(initialValue: item?.weekdays ?? [weekday])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(kind.color.gradient, in: .circle)
                        TextField("Название", text: $title)
                            .focused($focused)
                            .submitLabel(.done)
                    }
                }

                Section("Категория") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RoutineKind.allCases) { k in
                                Button { pick(k) } label: {
                                    Label(k.title, systemImage: k.icon)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .foregroundStyle(kind == k ? Color.white : k.color)
                                        .background(kind == k ? k.color : k.color.opacity(0.15), in: .capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets())
                }

                Section("Время") {
                    DatePicker("Начало", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("Длительность", selection: $duration) {
                        ForEach(Self.durations, id: \.self) { d in
                            Text(d == 0 ? "Без длительности" : durationText(d)).tag(d)
                        }
                    }
                    if duration > 0 {
                        LabeledContent("Окончание", value: Fmt.time(time.minutesOfDay + duration))
                    }
                }

                Section {
                    HStack(spacing: 6) {
                        ForEach(weekdayOrder, id: \.self) { wd in
                            let on = weekdays.contains(wd)
                            Button {
                                if on { weekdays.remove(wd) } else { weekdays.insert(wd) }
                            } label: {
                                Text(shortWeekday(wd))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(on ? Color.white : Color.primary)
                                    .background(
                                        on ? brand : Color.secondary.opacity(0.15),
                                        in: .rect(cornerRadius: 10)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)

                    HStack(spacing: 8) {
                        Button("Каждый день") { weekdays = Set(1...7) }
                        Button("Будни") { weekdays = [2, 3, 4, 5, 6] }
                        Button("Выходные") { weekdays = [1, 7] }
                        Spacer(minLength: 0)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } header: {
                    Text("Повторять по дням")
                } footer: {
                    if weekdays.isEmpty {
                        Text("Выберите хотя бы один день")
                            .foregroundStyle(.red)
                    }
                }

                if let original {
                    Section {
                        Button("Удалить из всех дней", role: .destructive) {
                            store.removeEverywhere(original)
                            dismiss()
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(original == nil ? "Новый пункт" : "Изменить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { if original == nil { focused = true } }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !weekdays.isEmpty
    }

    private func pick(_ k: RoutineKind) {
        if title.isEmpty || title == kind.title { title = k.title }
        if original == nil, k == .wake || k == .sleep { duration = 0 }
        kind = k
    }

    private func save() {
        var item = original ?? ScheduleItem(
            title: "", kind: kind, start: time.minutesOfDay, duration: duration, weekdays: weekdays
        )
        item.title = title.trimmingCharacters(in: .whitespaces)
        item.kind = kind
        item.start = time.minutesOfDay
        item.duration = duration
        item.weekdays = weekdays

        store.upsert(item)
        dismiss()
    }

    private static func date(fromMinutes m: Int) -> Date {
        cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
}

// MARK: - Правая вкладка: To-Do

struct TodoSheetTarget: Identifiable {
    let id = UUID()
    var todo: TodoItem?
}

struct TodoTab: View {
    @EnvironmentObject private var store: Store
    @State private var date = Date().startOfDay
    @State private var sheet: TodoSheetTarget?

    var body: some View {
        let todos = store.todos(on: date)
        let done = todos.filter(\.isDone).count

        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(date: $date)

                List {
                    if !todos.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Выполнено")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(done) из \(todos.count)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: Double(done), total: Double(todos.count))
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    ForEach(todos) { todo in
                        TodoRow(todo: todo)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation { store.delete(todo) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    sheet = TodoSheetTarget(todo: todo)
                                } label: {
                                    Label("Изменить", systemImage: "pencil")
                                }
                                Button {
                                    withAnimation {
                                        store.updateTodo(todo, title: todo.title, date: todo.date.addingDays(1))
                                    }
                                } label: {
                                    Label("Перенести на следующий день", systemImage: "calendar.badge.plus")
                                }
                                Button(role: .destructive) {
                                    withAnimation { store.delete(todo) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }
                .contentMargins(.bottom, 100, for: .scrollContent)
                .overlay {
                    if todos.isEmpty {
                        ContentUnavailableView(
                            "Нет задач",
                            systemImage: "checklist",
                            description: Text("Нажмите «+», чтобы добавить задачу на этот день")
                        )
                    }
                }
            }
            .pagerSwipe(2)
            .navigationTitle(cal.isDateInToday(date) ? "Сегодня" : Fmt.string(date, "EEEE").capFirst)
            .navigationSubtitle(Fmt.string(date, "d MMMM"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    SettingsButton()
                    Button("Сегодня") {
                        withAnimation(.snappy) { date = Date().startOfDay }
                    }
                    .disabled(cal.isDateInToday(date))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = TodoSheetTarget(todo: nil)
                    } label: {
                        Label("Добавить", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $sheet) { target in
            TodoEditor(date: date, editing: target.todo)
        }
    }
}

struct TodoRow: View {
    @EnvironmentObject private var store: Store
    let todo: TodoItem

    var body: some View {
        Button {
            withAnimation(.snappy) { store.toggle(todo) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.isDone ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(todo.title)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: todo.isDone)
    }
}

/// Окно новой / редактируемой задачи. По «Добавить» (или Return) закрывается само.
struct TodoEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var brand
    @FocusState private var focused: Bool

    private let editing: TodoItem?
    @State private var text: String
    @State private var date: Date

    init(date: Date, editing: TodoItem? = nil) {
        self.editing = editing
        _text = State(initialValue: editing?.title ?? "")
        _date = State(initialValue: (editing?.date ?? date).startOfDay)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Что нужно сделать?", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))

                HStack(spacing: 8) {
                    quick("Сегодня", Date().startOfDay)
                    quick("Завтра", Date().startOfDay.addingDays(1))
                    Spacer(minLength: 0)
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }

                Button(action: commit) {
                    Label(editing == nil ? "Добавить" : "Сохранить",
                          systemImage: editing == nil ? "plus" : "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(trimmed.isEmpty)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(editing == nil ? "Новая задача" : "Изменить задачу")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(330), .large])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }

    private func quick(_ title: String, _ day: Date) -> some View {
        let on = cal.isDate(date, inSameDayAs: day)
        return Button(title) { date = day }
            .buttonStyle(.bordered)
            .tint(on ? brand : Color.secondary)
            .controlSize(.small)
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        if let editing {
            store.updateTodo(editing, title: trimmed, date: date)
        } else {
            store.addTodo(trimmed, on: date)
        }
        dismiss()
    }
}

// MARK: - Левая вкладка: календарь на год

struct DaySelection: Identifiable {
    let date: Date
    var id: Date { date }
}

struct CalendarTab: View {
    @State private var year = cal.component(.year, from: Date())
    @State private var selected: DaySelection?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        ForEach(1...12, id: \.self) { m in
                            MonthView(year: year, month: m) { selected = DaySelection(date: $0) }
                                .id(m)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                }
                .contentMargins(.bottom, 100, for: .scrollContent)
                .onAppear { scrollToCurrent(proxy) }
                .onChange(of: year) { _, _ in scrollToCurrent(proxy) }
            }
            .pagerSwipe(0)
            .navigationTitle(String(year))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    SettingsButton()
                    Button("Сегодня") {
                        year = cal.component(.year, from: Date())
                    }
                    .disabled(year == cal.component(.year, from: Date()))
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                    Button { year += 1 } label: { Image(systemName: "chevron.right") }
                }
            }
        }
        .sheet(item: $selected) { sel in
            DayDetailSheet(date: sel.date)
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        let now = Date()
        let target = year == cal.component(.year, from: now) ? cal.component(.month, from: now) : 1
        withAnimation { proxy.scrollTo(target, anchor: .top) }
    }
}

struct MonthView: View {
    @Environment(\.brand) private var brand
    let year: Int
    let month: Int
    let onSelect: (Date) -> Void

    private var first: Date {
        cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    private var isCurrentMonth: Bool {
        let now = Date()
        return cal.component(.year, from: now) == year && cal.component(.month, from: now) == month
    }

    var body: some View {
        let offset = (first.weekday - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30

        VStack(alignment: .leading, spacing: 8) {
            Text(Fmt.string(first, "LLLL").capFirst)
                .font(.title2.bold())
                .foregroundStyle(isCurrentMonth ? brand : Color.primary)
                .padding(.horizontal, 4)

            HStack(spacing: 2) {
                ForEach(weekdayOrder, id: \.self) { wd in
                    Text(shortWeekday(wd))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<offset, id: \.self) { _ in
                    Color.clear.frame(height: 1)
                }
                ForEach(1...count, id: \.self) { d in
                    let date = cal.date(from: DateComponents(year: year, month: month, day: d)) ?? first
                    DayCell(date: date) { onSelect(date) }
                }
            }
        }
    }
}

struct DayCell: View {
    @EnvironmentObject private var store: Store
    @Environment(\.brand) private var brand
    let date: Date
    let action: () -> Void

    var body: some View {
        let todos = store.todos(on: date)
        let isToday = cal.isDateInToday(date)

        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isToday ? Color.white : Color.primary)
                    .frame(width: 22, height: 22)
                    .background {
                        if isToday { Circle().fill(brand) }
                    }

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(todos.prefix(3)) { t in
                        Text(t.title)
                            .font(.system(size: 8.5, weight: .medium))
                            .lineLimit(1)
                            .strikethrough(t.isDone)
                            .foregroundStyle(t.isDone ? .tertiary : .primary)
                            .padding(.horizontal, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                brand.opacity(t.isDone ? 0.07 : 0.2),
                                in: .rect(cornerRadius: 3)
                            )
                    }
                    if todos.count > 3 {
                        Text("+\(todos.count - 3)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            .padding(.horizontal, 2)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .top)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(brand, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Детали дня: дела + распорядок этого дня недели
struct DayDetailSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var brand

    let date: Date
    @State private var newTitle = ""

    var body: some View {
        let todos = store.todos(on: date)
        let routine = store.items(forWeekday: date.weekday)

        NavigationStack {
            List {
                Section("Дела") {
                    ForEach(todos) { todo in
                        TodoRow(todo: todo)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation { store.delete(todo) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(brand)
                        TextField("Новое дело", text: $newTitle)
                            .submitLabel(.done)
                            .onSubmit(add)
                    }
                }

                if !routine.isEmpty {
                    Section("Распорядок дня") {
                        ForEach(routine) { item in
                            ScheduleRow(item: item)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Fmt.string(date, "EEEE, d MMMM").capFirst)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addTodo(t, on: date)
        newTitle = ""
    }
}

// MARK: - Настройки

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("theme") private var theme = 0
    @AppStorage("accent") private var accent = 0
    @AppStorage("remTasks") private var remTasks = false
    @AppStorage("remRoutine") private var remRoutine = false
    @AppStorage("remListID") private var remListID = ""

    @State private var lists: [ReminderListInfo] = []
    @State private var showDenied = false
    @State private var showReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Внешний вид") {
                    Picker("Тема", selection: $theme) {
                        Text("Как в системе").tag(0)
                        Text("Светлая").tag(1)
                        Text("Тёмная").tag(2)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Цвет акцента")
                        HStack(spacing: 12) {
                            ForEach(Palette.colors.indices, id: \.self) { i in
                                Button { accent = i } label: {
                                    Circle()
                                        .fill(Palette.colors[i].gradient)
                                        .frame(width: 30, height: 30)
                                        .overlay {
                                            if accent == i {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Задачи в Напоминаниях", isOn: $remTasks)

                    if remTasks {
                        Picker("Список", selection: $remListID) {
                            if remListID.isEmpty {
                                Text("Распорядок дня").tag("")
                            }
                            ForEach(lists) { l in
                                Text(l.title).tag(l.id)
                            }
                        }

                        Button {
                            Task { await store.pullReminders() }
                        } label: {
                            Label("Синхронизировать сейчас", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    Toggle("Напоминать о распорядке", isOn: $remRoutine)
                } header: {
                    Text("Напоминания")
                } footer: {
                    Text("Задачи синхронизируются в обе стороны через список в приложении «Напоминания». Пункты распорядка создаются там повторяющимися напоминаниями с сигналом в момент начала.")
                }

                Section("Данные") {
                    Button("Удалить выполненные задачи") { store.clearCompleted() }
                    Button("Сбросить всё", role: .destructive) { showReset = true }
                }

                Section {
                    LabeledContent("Версия", value: "1.2")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .onAppear(perform: loadLists)
            .onChange(of: remTasks) { _, on in
                Task { await tasksChanged(on) }
            }
            .onChange(of: remRoutine) { _, on in
                Task { await routineChanged(on) }
            }
            .onChange(of: remListID) { _, _ in
                Task { await store.pullReminders() }
            }
            .alert("Нет доступа к Напоминаниям", isPresented: $showDenied) {
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Разрешите доступ: Настройки → Приложения → Распорядок → Напоминания.")
            }
            .confirmationDialog(
                "Удалить все задачи и вернуть распорядок по умолчанию?",
                isPresented: $showReset,
                titleVisibility: .visible
            ) {
                Button("Сбросить", role: .destructive) { store.resetAll() }
            }
        }
    }

    private func loadLists() {
        lists = store.reminders.allLists().map {
            ReminderListInfo(id: $0.calendarIdentifier, title: $0.title)
        }
    }

    private func tasksChanged(_ on: Bool) async {
        guard on else { return }
        if await store.enableTaskSync() {
            loadLists()
        } else {
            remTasks = false
            showDenied = true
        }
    }

    private func routineChanged(_ on: Bool) async {
        if on {
            if await store.enableRoutineSync() {
                loadLists()
            } else {
                remRoutine = false
                showDenied = true
            }
        } else {
            store.disableRoutineSync()
        }
    }
}
