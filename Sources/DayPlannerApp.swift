//
//  DayPlannerApp.swift
//  Распорядок дня + To-Do  (v2.0)
//
//  Требования: Xcode 26+, iOS 26.0+ (Liquid Glass).
//  Для Напоминаний в Info.plist нужен ключ NSRemindersFullAccessUsageDescription
//  (он уже добавлен в build-ipa.yml).
//  ИИ-помощник работает через OpenRouter: ключ вводится в приложении (Настройки или окно чата).
//

import SwiftUI
import UIKit
import EventKit
import Security
import UniformTypeIdentifiers

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

    /// Цвета иконки для категории «Другое» (0 — серый по умолчанию)
    static let iconColors: [Color] = [.gray, .red, .orange, .yellow, .green, .blue, .purple, .pink]

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

extension Notification.Name {
    /// Нажата плавающая кнопка «+» (object — номер вкладки)
    static let plannerAdd = Notification.Name("plannerAdd")
}

/// Ключ дня (гггг мм дд числом) — для списка пропущенных повторов
private func dayKey(_ d: Date) -> Int {
    let c = cal.dateComponents([.year, .month, .day], from: d)
    return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
}

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

    var span: Range<Int> {
        switch self {
        case .morning: 240..<720
        case .day: 720..<1080
        case .evening: 1080..<1440
        case .night: 0..<240
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
    var icon: String?       // своя иконка (SF Symbol) — только для категории «Другое»
    var iconColor: Int?     // индекс в Palette.iconColors — только для категории «Другое»

    var end: Int { start + duration }

    /// Иконка для показа: у «Другое» — выбранная, у остальных категорий — своя
    var displayIcon: String {
        kind == .other ? (icon ?? RoutineKind.other.icon) : kind.icon
    }

    /// Цвет кружка: у «Другое» — выбранный, у остальных категорий — свой
    var displayColor: Color {
        guard kind == .other, let i = iconColor, Palette.iconColors.indices.contains(i) else {
            return kind.color
        }
        return Palette.iconColors[i]
    }
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var isDone = false
    var reminderID: String?
    var seriesID: UUID?     // повторяющаяся задача: к какой серии относится
}

/// Повторяющаяся задача: по выбранным дням недели, по желанию — до даты.
/// Каждое повторение — отдельная задача со своей отметкой «выполнено».
struct TodoSeries: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var weekdays: Set<Int>   // Calendar.weekday
    var start: Date
    var end: Date?
    var skipped: Set<Int> = []   // удалённые/перенесённые дни (ключи dayKey)
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
            // @Sendable: колбэк приходит не на главном потоке
            eventStore.fetchReminders(matching: predicate) { @Sendable result in
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

    /// Переносит напоминание в текущий выбранный список задач
    func moveToTaskList(id: String?) {
        guard tasksOn, let r = reminder(id), let lst = taskList,
              r.calendar.calendarIdentifier != lst.calendarIdentifier else { return }
        r.calendar = lst
        try? eventStore.save(r, commit: true)
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
    @Published private(set) var series: [TodoSeries] = []

    /// На сколько дней вперёд создаются повторы (дальше — по мере наступления)
    private let horizonDays = 28

    let reminders = RemindersService()

    private struct Snapshot: Codable {
        var schedule: [ScheduleItem]
        var todos: [TodoItem]
        var series: [TodoSeries]?
    }

    private let url = URL.documentsDirectory.appending(path: "planner.json")

    init() {
        if let data = try? Data(contentsOf: url) {
            if let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
                schedule = snap.schedule
                todos = snap.todos
                series = snap.series ?? []
            } else {
                // файл не прочитался — не затираем его, а откладываем копию
                let broken = URL.documentsDirectory.appending(path: "planner-broken-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: url, to: broken)
                save()
            }
        } else {
            save()
        }
        if !series.isEmpty { extendSeries() }
    }

    // Резервная копия

    /// Данные в JSON для экспорта
    func exportData() -> Data {
        let snap = Snapshot(schedule: schedule, todos: todos, series: series)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(snap)) ?? Data()
    }

    /// Заменяет все данные содержимым копии. Связи с Напоминаниями пересоздаются.
    func importData(_ data: Data) async -> Bool {
        guard let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return false }
        for t in todos { reminders.remove(id: t.reminderID) }
        for s in schedule { reminders.removeRoutine(s) }

        schedule = snap.schedule.map { var s = $0; s.reminderID = nil; return s }
        todos = snap.todos.map { var t = $0; t.reminderID = nil; return t }
        series = snap.series ?? []
        save()

        if reminders.routineOn { _ = await enableRoutineSync() }
        if reminders.tasksOn { _ = await enableTaskSync() }
        extendSeries()
        return true
    }

    /// Типовой распорядок для быстрого старта (на все дни недели)
    func applyTemplate() {
        let all = Set(1...7)
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        let template: [ScheduleItem] = [
            ScheduleItem(title: "Подъём", kind: .wake, start: 7 * 60, duration: 0, weekdays: all),
            ScheduleItem(title: "Завтрак", kind: .meal, start: 7 * 60 + 30, duration: 30, weekdays: all),
            ScheduleItem(title: "Работа", kind: .work, start: 9 * 60, duration: 4 * 60, weekdays: weekdays),
            ScheduleItem(title: "Обед", kind: .meal, start: 13 * 60, duration: 60, weekdays: all),
            ScheduleItem(title: "Работа", kind: .work, start: 14 * 60, duration: 4 * 60, weekdays: weekdays),
            ScheduleItem(title: "Спорт", kind: .sport, start: 18 * 60 + 30, duration: 60, weekdays: [2, 4, 6]),
            ScheduleItem(title: "Ужин", kind: .meal, start: 19 * 60 + 30, duration: 30, weekdays: all),
            ScheduleItem(title: "Свободное время", kind: .free, start: 20 * 60, duration: 150, weekdays: all),
            ScheduleItem(title: "Отбой", kind: .sleep, start: 23 * 60, duration: 8 * 60, weekdays: all)
        ]
        for item in template { upsert(item) }
    }

    /// Пункты, пересекающиеся по времени с данным (с учётом перехода за полночь)
    func conflicts(start: Int, duration: Int, weekdays: Set<Int>, excluding id: UUID?) -> [ScheduleItem] {
        let len = max(duration, 1)
        func spans(_ s: Int, _ l: Int, _ wd: Int) -> [Range<Int>] {
            // минуты недели: день недели (Пн = 0) * 1440 + время
            let dayIndex = (wd - cal.firstWeekday + 7) % 7
            let a = dayIndex * 1440 + s
            let week = 7 * 1440
            let r = a..<(a + l)
            return r.upperBound > week ? [a..<week, 0..<(r.upperBound - week)] : [r]
        }
        let mine = weekdays.flatMap { spans(start, len, $0) }
        return schedule.filter { other in
            guard other.id != id else { return false }
            let theirs = other.weekdays.flatMap { spans(other.start, max(other.duration, 1), $0) }
            return mine.contains { m in theirs.contains { $0.overlaps(m) } }
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
        if !cal.isDate(todos[i].date, inSameDayAs: date) { skip(todos[i]) }
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
        skip(todo)
        reminders.remove(id: todo.reminderID)
        todos.removeAll { $0.id == todo.id }
        save()
    }

    /// Сколько дел стоит на выбранных датах
    func todoCount(on dates: [Date]) -> Int {
        let keys = Set(dates.map { dayKey($0) })
        return todos.filter { keys.contains(dayKey($0.date)) }.count
    }

    /// Удаляет все дела на выбранных датах (повторы на эти даты не вернутся)
    func clearTodos(on dates: [Date]) {
        let keys = Set(dates.map { dayKey($0) })
        for t in todos where keys.contains(dayKey(t.date)) {
            skip(t)
            reminders.remove(id: t.reminderID)
        }
        todos.removeAll { keys.contains(dayKey($0.date)) }
        save()
    }

    /// Невыполненные разовые задачи с прошлых дней (повторы не считаются — это привычки)
    func overdue() -> [TodoItem] {
        let today = Date().startOfDay
        return todos
            .filter { !$0.isDone && $0.seriesID == nil && $0.date < today }
            .sorted { $0.date < $1.date }
    }

    func moveToToday(_ items: [TodoItem]) {
        let today = Date().startOfDay
        for t in items {
            guard let i = todos.firstIndex(where: { $0.id == t.id }) else { continue }
            todos[i].date = today
            reminders.update(id: todos[i].reminderID, date: today)
        }
        save()
    }

    func clearCompleted() {
        for t in todos where t.isDone {
            skip(t)
            reminders.remove(id: t.reminderID)
        }
        todos.removeAll { $0.isDone }
        save()
    }

    func resetAll() {
        for t in todos { reminders.remove(id: t.reminderID) }
        for s in schedule { reminders.removeRoutine(s) }
        todos = []
        series = []
        schedule = []
        save()
    }

    // Повторяющиеся задачи

    func addRepeating(_ title: String, from date: Date, weekdays: Set<Int>, until: Date?) {
        let s = TodoSeries(title: title, weekdays: weekdays, start: date.startOfDay, end: until?.startOfDay)
        series.append(s)
        generate(for: s, from: s.start)
        save()
    }

    /// Дозаполняет повторы на горизонт вперёд (вызывается при запуске и при возврате в приложение)
    func extendSeries() {
        let today = Date().startOfDay
        series.removeAll { s in
            if let end = s.end { return end < today }
            return false
        }
        for s in series { generate(for: s, from: max(s.start, today)) }
        save()
    }

    /// Удаляет эту серию: будущие невыполненные повторы пропадают, прошлые остаются
    func deleteSeries(of todo: TodoItem) {
        guard let sid = todo.seriesID else { return }
        let today = Date().startOfDay
        for t in todos where t.seriesID == sid && t.date >= today && !t.isDone {
            reminders.remove(id: t.reminderID)
        }
        todos.removeAll { $0.seriesID == sid && $0.date >= today && !$0.isDone }
        for i in todos.indices where todos[i].seriesID == sid { todos[i].seriesID = nil }
        series.removeAll { $0.id == sid }
        save()
    }

    private func generate(for s: TodoSeries, from first: Date) {
        let today = Date().startOfDay
        var limit = today.addingDays(horizonDays)
        if let end = s.end, end < limit { limit = end }
        var day = max(first.startOfDay, today.addingDays(-366))
        var created: [TodoItem] = []
        while day <= limit {
            if s.weekdays.contains(day.weekday),
               !s.skipped.contains(dayKey(day)),
               !todos.contains(where: { $0.seriesID == s.id && cal.isDate($0.date, inSameDayAs: day) }) {
                let rid = reminders.create(title: s.title, date: day)
                created.append(TodoItem(title: s.title, date: day, reminderID: rid, seriesID: s.id))
            }
            day = day.addingDays(1)
        }
        if !created.isEmpty { todos.append(contentsOf: created) }
    }

    /// Запоминает, что этот день серии удалён/перенесён — чтобы он не появился снова
    private func skip(_ todo: TodoItem) {
        guard let sid = todo.seriesID,
              let i = series.firstIndex(where: { $0.id == sid }) else { return }
        series[i].skipped.insert(dayKey(todo.date))
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

    /// Сменили список в Напоминаниях — переносим туда уже связанные задачи, чтобы не было дублей
    func taskListChanged() async {
        for t in todos { reminders.moveToTaskList(id: t.reminderID) }
        await pullReminders()
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
                skip(list[i])
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
        let snap = Snapshot(schedule: schedule, todos: todos, series: series)
        do {
            try JSONEncoder().encode(snap).write(to: url, options: .atomic)
        } catch {
            print("Save error:", error)
        }
    }
}

// MARK: - Пейджер вкладок (UIKit)
//
// Нативный постраничный UIScrollView + UIHostingController на каждую вкладку:
//  • свайп листает вкладки с обычной физикой iOS (инерция, «резинка» по краям);
//  • полоса недели (свой горизонтальный скролл) листается сама, вкладки не трогает;
//  • на последней вкладке свайп влево отдаётся строке задачи (удаление).

final class PagingScrollView: UIScrollView {
    /// Можно ли начинать листание вкладок для жеста с таким смещением по X
    var allowPaging: ((CGFloat) -> Bool)?

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let t = panGestureRecognizer.translation(in: self)
        let v = panGestureRecognizer.velocity(in: self)
        let dx = t.x != 0 ? t.x : v.x
        let dy = t.y != 0 ? t.y : v.y
        guard abs(dx) > abs(dy) else { return false }
        if hasNestedHorizontalScroll(at: panGestureRecognizer.location(in: self)) { return false }
        if let allowPaging, !allowPaging(dx) { return false }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    private func hasNestedHorizontalScroll(at point: CGPoint) -> Bool {
        var view = hitTest(point, with: nil)
        while let current = view, current !== self {
            if let scroll = current as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 1 {
                return true
            }
            view = current.superview
        }
        return false
    }
}

final class PagerController: UIViewController, UIScrollViewDelegate {
    private let scrollView = PagingScrollView()
    private var hosts: [UIHostingController<AnyView>] = []
    private var lastToken = ""
    private var isAnimating = false

    var currentPage = 1
    var onPageChange: ((Int) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.isDirectionalLockEnabled = true
        scrollView.delaysContentTouches = false
        scrollView.delegate = self
        scrollView.allowPaging = { [weak self] dx in
            guard let self else { return true }
            // последняя вкладка: свайп влево — удаление строки, а не листание
            return !(self.currentPage == self.hosts.count - 1 && dx < 0)
        }
        view.addSubview(scrollView)
    }

    func apply(pages: [AnyView], token: String) {
        loadViewIfNeeded()
        if hosts.isEmpty {
            for page in pages {
                let host = UIHostingController(rootView: page)
                host.view.backgroundColor = .clear
                addChild(host)
                scrollView.addSubview(host.view)
                host.didMove(toParent: self)
                hosts.append(host)
            }
            lastToken = token
            view.setNeedsLayout()
        } else if token != lastToken {
            lastToken = token
            for (host, page) in zip(hosts, pages) { host.rootView = page }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0 else { return }
        scrollView.frame = view.bounds
        scrollView.contentSize = CGSize(width: w * CGFloat(hosts.count), height: h)
        for (i, host) in hosts.enumerated() {
            host.view.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
        }
        if !scrollView.isTracking, !scrollView.isDecelerating, !isAnimating {
            scrollView.contentOffset = CGPoint(x: CGFloat(currentPage) * w, y: 0)
        }
    }

    /// Переход на вкладку (нажатие в нижней панели)
    func goTo(_ page: Int, animated: Bool) {
        guard page != currentPage, hosts.indices.contains(page) else { return }
        currentPage = page
        let w = view.bounds.width
        guard w > 0 else { return }
        isAnimating = animated
        scrollView.setContentOffset(CGPoint(x: CGFloat(page) * w, y: 0), animated: animated)
    }

    func scrollViewDidScroll(_ sv: UIScrollView) {
        guard sv.isTracking || sv.isDecelerating else { return }
        let w = view.bounds.width
        guard w > 0 else { return }
        let page = max(0, min(hosts.count - 1, Int((sv.contentOffset.x / w).rounded())))
        if page != currentPage {
            currentPage = page
            onPageChange?(page)
        }
    }

    func scrollViewDidEndScrollingAnimation(_ sv: UIScrollView) {
        isAnimating = false
    }
}

struct PagerView: UIViewControllerRepresentable {
    @Binding var selection: Int
    let pages: [AnyView]
    let token: String

    func makeUIViewController(context: Context) -> PagerController {
        let vc = PagerController()
        vc.currentPage = selection
        vc.onPageChange = changeHandler()
        vc.apply(pages: pages, token: token)
        return vc
    }

    func updateUIViewController(_ vc: PagerController, context: Context) {
        vc.onPageChange = changeHandler()
        vc.apply(pages: pages, token: token)
        vc.goTo(selection, animated: true)
    }

    private func changeHandler() -> (Int) -> Void {
        let binding = $selection
        return { page in
            withAnimation(.snappy) { binding.wrappedValue = page }
        }
    }
}

// MARK: - Корневой экран: 3 вкладки

struct RootView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var phase
    @AppStorage("theme") private var theme = 0
    @AppStorage("accent") private var accent = 0
    @State private var tab = 1   // по умолчанию — центральная
    @State private var showAI = false
    @StateObject private var aiChat = AIChat()   // переписка живёт, пока открыто приложение

    var body: some View {
        ZStack(alignment: .bottom) {
            PagerView(
                selection: $tab,
                pages: [page(CalendarTab()), page(ScheduleTab()), page(TodoTab())],
                token: "\(theme)-\(accent)"
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                if tab != 0 {
                    HStack(spacing: 12) {
                        Spacer()
                        FloatingAIButton { showAI = true }
                        FloatingAddButton(label: tab == 1 ? "Новый пункт" : "Новая задача") {
                            NotificationCenter.default.post(name: .plannerAdd, object: tab)
                        }
                    }
                    .padding(.horizontal, 20)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                GlassTabBar(selection: $tab)
            }
            .animation(.snappy, value: tab)
        }
        .sensoryFeedback(.selection, trigger: tab)
        .sheet(isPresented: $showAI) {
            AIChatView(chat: aiChat)
        }
        .task {
            store.extendSeries()
            await store.pullReminders()
        }
        .onChange(of: phase) { _, new in
            if new == .active {
                store.extendSeries()
                Task { await store.pullReminders() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await store.pullReminders() }
        }
    }

    /// Каждая вкладка живёт в своём UIHostingController — окружение передаём вручную
    private func page<V: View>(_ view: V) -> AnyView {
        let color = Palette.color(accent)
        return AnyView(
            view
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .environment(\.calendar, Calendar.planner)
                .environment(\.brand, color)
                .tint(color)
                .preferredColorScheme(Palette.scheme(theme))
        )
    }
}

/// Плавающая кнопка «+» (правый нижний угол, поверх списка, над панелью вкладок)
struct FloatingAddButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }
}

/// Плавающая кнопка ИИ-помощника (слева от «+»)
struct FloatingAIButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("ИИ-помощник")
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
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: weekIndex)
        .onChange(of: weekIndex) { _, new in
            // неделю пролистали — выбираем тот же день недели в новой неделе
            guard let new, new != Self.index(of: date) else { return }
            let offset = (date.weekday - cal.firstWeekday + 7) % 7
            date = Self.start(of: new).addingDays(offset)
        }
        .onChange(of: date) { _, new in
            // дату сменили («Сегодня», выбор дня) — докручиваем полосу до нужной недели
            let i = Self.index(of: new)
            if weekIndex != i {
                withAnimation(.snappy) { weekIndex = i }
            }
        }
    }

    private func weekRow(_ i: Int) -> some View {
        let start = Self.start(of: i)
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { k in
                dayCell(start.addingDays(k))
            }
        }
        .padding(.horizontal, 8)
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = cal.isDate(day, inSameDayAs: date)
        let isToday = cal.isDateInToday(day)

        return Button {
            withAnimation(.snappy) { date = day.startOfDay }
        } label: {
            VStack(spacing: 6) {
                Text(Fmt.string(day, "EEEEE").uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(cal.component(.day, from: day))")
                    .font(.title3.weight(.medium).monospacedDigit())
                    .foregroundStyle(selected ? Color.white : (isToday ? brand : Color.primary))
                    .frame(width: 40, height: 40)
                    .background {
                        if selected {
                            Circle()
                                .fill(brand)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Заголовок по центру панели: месяц крупно, под ним день недели и число
struct DayTitle: View {
    let date: Date

    var body: some View {
        VStack(spacing: 1) {
            Text(Fmt.string(date, "LLLL").capFirst)
                .font(.title3.weight(.semibold))
            Text(Fmt.string(date, "EEEE, d").capFirst)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Центральная вкладка: распорядок дня

struct EditorTarget: Identifiable {
    let id = UUID()
    var item: ScheduleItem?
    var weekday: Int
}

/// Отрезок пункта внутри одного дня (spill — продолжение пункта, начатого накануне)
struct DaySegment: Identifiable {
    let item: ScheduleItem
    let start: Int
    let end: Int
    let spill: Bool

    var id: String { item.id.uuidString + (spill ? "-s" : "") }
}

struct ScheduleTab: View {
    @EnvironmentObject private var store: Store
    @State private var date = Date().startOfDay
    @State private var editor: EditorTarget?
    @State private var now = Date()

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let segs = segments(for: date)
        let nowIDs = currentIDs(in: segs)

        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(date: $date)

                List {
                    ForEach(DayPart.allCases) { part in
                        let lower = part.span.lowerBound
                        // пункты, начавшиеся раньше и ещё идущие в этой части суток
                        let continuing = segs.filter { seg in
                            seg.spill ? seg.end > lower : (seg.start < lower && seg.end > lower)
                        }
                        let starting = segs.filter { !$0.spill && DayPart.of($0.start) == part }

                        if !continuing.isEmpty || !starting.isEmpty {
                            Section {
                                ForEach(continuing) { seg in
                                    Button {
                                        openEditor(seg)
                                    } label: {
                                        ContinuationRow(segment: seg, isNow: nowIDs.contains(seg.item.id))
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu { menuItems(for: seg) }
                                }
                                ForEach(starting) { seg in
                                    Button {
                                        openEditor(seg)
                                    } label: {
                                        ScheduleRow(item: seg.item, isNow: nowIDs.contains(seg.item.id))
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu { menuItems(for: seg) }
                                }
                            } header: {
                                PartHeader(part: part)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .contentMargins(.bottom, 170, for: .scrollContent)
                .overlay {
                    if segs.isEmpty {
                        emptyState
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }
                ToolbarItem(placement: .principal) {
                    DayTitle(date: date)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) { date = Date().startOfDay }
                    } label: {
                        Label("Вернуться к сегодняшнему дню", systemImage: "arrow.backward")
                    }
                    .disabled(cal.isDateInToday(date))
                }
            }
        }
        .sheet(item: $editor) { target in
            ScheduleEditor(item: target.item, weekday: target.weekday)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plannerAdd)) { note in
            if (note.object as? Int) == 1 {
                editor = EditorTarget(item: nil, weekday: date.weekday)
            }
        }
        .onReceive(ticker) { now = $0 }
    }

    /// Пустой день; если распорядка нет совсем — предлагаем типовой
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Распорядок пуст", systemImage: "clock")
        } description: {
            Text("Нажмите «+», чтобы добавить пункт на этот день")
        } actions: {
            if store.schedule.isEmpty {
                Button("Заполнить типовым распорядком") {
                    withAnimation { store.applyTemplate() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// Отрезки пунктов этого дня + продолжение вчерашних пунктов, перешедших за полночь
    private func segments(for day: Date) -> [DaySegment] {
        let own = store.items(forWeekday: day.weekday).map {
            DaySegment(item: $0, start: $0.start, end: min($0.end, 1440), spill: false)
        }
        let spilled = store.items(forWeekday: day.addingDays(-1).weekday)
            .filter { $0.end > 1440 }
            .map { DaySegment(item: $0, start: 0, end: $0.end - 1440, spill: true) }
        return (own + spilled).sorted { $0.start < $1.start }
    }

    private func weekday(of seg: DaySegment) -> Int {
        seg.spill ? date.addingDays(-1).weekday : date.weekday
    }

    private func openEditor(_ seg: DaySegment) {
        editor = EditorTarget(item: seg.item, weekday: weekday(of: seg))
    }

    @ViewBuilder
    private func menuItems(for seg: DaySegment) -> some View {
        Button {
            openEditor(seg)
        } label: {
            Label("Изменить", systemImage: "pencil")
        }
        Button(role: .destructive) {
            withAnimation { store.remove(seg.item, fromWeekday: weekday(of: seg)) }
        } label: {
            Label("Убрать из этого дня", systemImage: "calendar.badge.minus")
        }
        Button(role: .destructive) {
            withAnimation { store.removeEverywhere(seg.item) }
        } label: {
            Label("Удалить из всех дней", systemImage: "trash")
        }
    }

    /// Пункты, которые идут прямо сейчас (только для сегодняшнего дня).
    /// Пункт без длительности считается «текущим» первые 5 минут.
    private func currentIDs(in segs: [DaySegment]) -> Set<UUID> {
        guard cal.isDateInToday(date) else { return [] }
        let m = now.minutesOfDay
        let active = segs.filter { seg in
            if seg.spill { return m < seg.end }
            let end = seg.item.duration > 0 ? seg.end : seg.start + 5
            return seg.start <= m && m < end
        }
        return Set(active.map { $0.item.id })
    }
}

/// Строка-продолжение: пункт начался раньше и ещё идёт в этой части суток
struct ContinuationRow: View {
    @Environment(\.brand) private var brand
    let segment: DaySegment
    var isNow = false

    var body: some View {
        let item = segment.item

        HStack(spacing: 14) {
            Image(systemName: "arrow.turn.down.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 50, alignment: .trailing)

            Image(systemName: item.displayIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(item.displayColor.gradient, in: .circle)
                .padding(.horizontal, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                Text("продолжается до \(Fmt.time(item.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .padding(.vertical, 2)
        .contentShape(Rectangle())
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

            Image(systemName: item.displayIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(item.displayColor.gradient, in: .circle)

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
        let sameAsKind = item.title == item.kind.title
        if item.duration > 0 {
            return sameAsKind
                ? durationText(item.duration)
                : "\(item.kind.title) · \(durationText(item.duration))"
        }
        return sameAsKind ? nil : item.kind.title
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
    @State private var icon: String
    @State private var iconColor: Int

    init(item: ScheduleItem?, weekday: Int) {
        original = item
        _title = State(initialValue: item?.title ?? "")
        _kind = State(initialValue: item?.kind ?? .other)
        _time = State(initialValue: Self.date(fromMinutes: item?.start ?? 9 * 60))
        _duration = State(initialValue: item?.duration ?? 0)
        _weekdays = State(initialValue: item?.weekdays ?? [weekday])
        _icon = State(initialValue: item?.icon ?? RoutineKind.other.icon)
        _iconColor = State(initialValue: item?.iconColor ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: kind == .other ? icon : kind.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(previewColor.gradient, in: .circle)
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

                if kind == .other {
                    Section("Иконка") {
                        NavigationLink {
                            IconPicker(selection: $icon)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(previewColor.gradient, in: .circle)
                                Text("Выбрать иконку")
                            }
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Palette.iconColors.indices, id: \.self) { i in
                                    Button { iconColor = i } label: {
                                        Circle()
                                            .fill(Palette.iconColors[i].gradient)
                                            .frame(width: 30, height: 30)
                                            .overlay {
                                                if iconColor == i {
                                                    Image(systemName: "checkmark")
                                                        .font(.caption.bold())
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    DatePicker("Начало", selection: $time, displayedComponents: .hourAndMinute)
                    Toggle("Окончание", isOn: hasEnd)
                    if duration > 0 {
                        DatePicker("Конец", selection: endTime, displayedComponents: .hourAndMinute)
                        LabeledContent("Длительность", value: durationText(duration))
                    }
                } header: {
                    Text("Время")
                } footer: {
                    if let warning = conflictText {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
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

    /// Текст предупреждения о пересечении с другими пунктами (nil — пересечений нет)
    private var conflictText: String? {
        let overlap: [ScheduleItem] = store.conflicts(
            start: time.minutesOfDay, duration: duration,
            weekdays: weekdays, excluding: original?.id
        )
        guard !overlap.isEmpty else { return nil }
        let names: [String] = overlap.map { item in
            let t: String = Fmt.time(item.start)
            return item.title + " (" + t + ")"
        }
        return "Пересекается: " + names.joined(separator: ", ")
    }

    private var previewColor: Color {
        guard kind == .other, Palette.iconColors.indices.contains(iconColor) else { return kind.color }
        return Palette.iconColors[iconColor]
    }

    /// Переключатель «Окончание»: включён, если есть длительность
    private var hasEnd: Binding<Bool> {
        Binding(
            get: { duration > 0 },
            set: { duration = $0 ? 60 : 0 }
        )
    }

    /// Своё время окончания; если оно раньше начала — значит, на следующие сутки.
    /// При смене начала длительность сохраняется, конец сдвигается вместе с ним.
    private var endTime: Binding<Date> {
        Binding(
            get: { Self.date(fromMinutes: (time.minutesOfDay + duration) % 1440) },
            set: { newEnd in
                let diff = (newEnd.minutesOfDay - time.minutesOfDay + 1440) % 1440
                if diff > 0 { duration = diff }
            }
        )
    }

    private func pick(_ k: RoutineKind) {
        if title.isEmpty || title == kind.title { title = k.title }
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
        item.icon = kind == .other ? icon : nil
        item.iconColor = kind == .other ? iconColor : nil

        store.upsert(item)
        dismiss()
    }

    private static func date(fromMinutes m: Int) -> Date {
        cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
}

// MARK: - Выбор иконки (SF Symbols)

struct IconGroup: Identifiable {
    let id: String
    let icons: [String]
}

struct IconPicker: View {
    @Binding var selection: String
    @Environment(\.brand) private var brand
    @State private var custom = ""

    private static func exists(_ name: String) -> Bool {
        !name.isEmpty && UIImage(systemName: name) != nil
    }

    private static let groups: [IconGroup] = [
        IconGroup(id: "Дом и быт", icons: [
            "house.fill", "bed.double.fill", "shower.fill", "washer.fill", "trash.fill", "cart.fill",
            "bag.fill", "lightbulb.fill", "key.fill", "hammer.fill", "wrench.and.screwdriver.fill", "paintbrush.fill"
        ]),
        IconGroup(id: "Еда и напитки", icons: [
            "cup.and.saucer.fill", "fork.knife", "wineglass.fill", "birthday.cake.fill", "carrot.fill",
            "takeoutbag.and.cup.and.straw.fill", "waterbottle.fill", "mug.fill"
        ]),
        IconGroup(id: "Спорт и здоровье", icons: [
            "figure.run", "figure.walk", "dumbbell.fill", "bicycle", "figure.yoga", "figure.pool.swim",
            "heart.fill", "cross.case.fill", "pills.fill", "stethoscope", "bandage.fill", "brain.head.profile",
            "drop.fill", "flame.fill", "soccerball", "figure.mind.and.body"
        ]),
        IconGroup(id: "Работа и учёба", icons: [
            "briefcase.fill", "laptopcomputer", "desktopcomputer", "book.fill", "graduationcap.fill", "pencil",
            "doc.text.fill", "folder.fill", "envelope.fill", "phone.fill", "calendar", "chart.bar.fill",
            "person.2.fill", "bubble.left.fill"
        ]),
        IconGroup(id: "Транспорт и поездки", icons: [
            "car.fill", "bus.fill", "tram.fill", "airplane", "fuelpump.fill", "map.fill", "location.fill",
            "suitcase.fill", "tent.fill", "beach.umbrella.fill"
        ]),
        IconGroup(id: "Отдых и хобби", icons: [
            "gamecontroller.fill", "tv.fill", "headphones", "music.note", "film.fill", "camera.fill",
            "guitars.fill", "theatermasks.fill", "party.popper.fill", "book.closed.fill", "puzzlepiece.fill",
            "paintpalette.fill", "pawprint.fill", "leaf.fill"
        ]),
        IconGroup(id: "Разное", icons: [
            "star.fill", "sun.max.fill", "moon.fill", "cloud.fill", "snowflake", "bolt.fill", "gift.fill",
            "bell.fill", "flag.fill", "creditcard.fill", "banknote.fill", "scissors", "hands.clap.fill",
            "face.smiling.fill", "sparkles", "bookmark.fill"
        ])
    ]

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    TextField("например, sparkles", text: $custom)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    if Self.exists(trimmedCustom) {
                        Image(systemName: trimmedCustom)
                            .font(.title3)
                            .foregroundStyle(brand)
                    }
                }
            } header: {
                Text("Своё название SF Symbol")
            } footer: {
                Text("Введите название любого символа из набора SF Symbols — он применится сразу.")
            }

            ForEach(Self.groups) { group in
                Section(group.id) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(group.icons.filter { Self.exists($0) }, id: \.self) { name in
                            Button {
                                selection = name
                            } label: {
                                Image(systemName: name)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(selection == name ? Color.white : Color.primary)
                                    .background(
                                        selection == name ? brand : Color.secondary.opacity(0.12),
                                        in: .circle
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Иконка")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: custom) { _, _ in
            if Self.exists(trimmedCustom) { selection = trimmedCustom }
        }
    }

    private var trimmedCustom: String {
        custom.trimmingCharacters(in: .whitespaces)
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
        let overdue = cal.isDateInToday(date) ? store.overdue() : []

        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(date: $date)

                List {
                    if !overdue.isEmpty {
                        OverdueSection(items: overdue)
                    }

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
                                if todo.seriesID != nil {
                                    Button(role: .destructive) {
                                        withAnimation { store.deleteSeries(of: todo) }
                                    } label: {
                                        Label("Удалить все повторы", systemImage: "trash.circle")
                                    }
                                }
                                Button(role: .destructive) {
                                    withAnimation { store.delete(todo) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }
                .contentMargins(.bottom, 170, for: .scrollContent)
                .overlay {
                    if todos.isEmpty && overdue.isEmpty {
                        ContentUnavailableView(
                            "Нет задач",
                            systemImage: "checklist",
                            description: Text("Нажмите «+», чтобы добавить задачу на этот день")
                        )
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }
                ToolbarItem(placement: .principal) {
                    DayTitle(date: date)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) { date = Date().startOfDay }
                    } label: {
                        Label("Вернуться к сегодняшнему дню", systemImage: "arrow.backward")
                    }
                    .disabled(cal.isDateInToday(date))
                }
            }
        }
        .sheet(item: $sheet) { target in
            TodoEditor(date: date, editing: target.todo)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plannerAdd)) { note in
            if (note.object as? Int) == 2 {
                sheet = TodoSheetTarget(todo: nil)
            }
        }
    }
}

/// Невыполненные задачи с прошлых дней (показываются на сегодняшнем дне)
struct OverdueSection: View {
    @EnvironmentObject private var store: Store
    let items: [TodoItem]

    var body: some View {
        Section {
            ForEach(items) { todo in
                row(todo)
            }
        } header: {
            header
        }
    }

    private var header: some View {
        HStack {
            Label("Просрочено", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(Color.red)
            Spacer()
            Button("Всё на сегодня") {
                withAnimation { store.moveToToday(items) }
            }
            .font(.caption.weight(.semibold))
        }
        .textCase(nil)
    }

    private func row(_ todo: TodoItem) -> some View {
        HStack(spacing: 8) {
            TodoRow(todo: todo)
            Text(Fmt.string(todo.date, "d MMM"))
                .font(.caption)
                .foregroundStyle(Color.red)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation { store.moveToToday([todo]) }
            } label: {
                Label("На сегодня", systemImage: "arrow.uturn.right")
            }
            .tint(Color.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { store.delete(todo) }
            } label: {
                Label("Удалить", systemImage: "trash")
            }
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
                if todo.seriesID != nil {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
    @State private var repeatOn = false
    @State private var weekdays: Set<Int>
    @State private var limitOn = false
    @State private var until: Date
    @State private var detent: PresentationDetent = .height(340)

    init(date: Date, editing: TodoItem? = nil) {
        self.editing = editing
        let day = (editing?.date ?? date).startOfDay
        _text = State(initialValue: editing?.title ?? "")
        _date = State(initialValue: day)
        _weekdays = State(initialValue: [day.weekday])
        _until = State(initialValue: day.addingDays(28))
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }
    private var canCommit: Bool { !trimmed.isEmpty && !(repeatOn && weekdays.isEmpty) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TextField("Что нужно сделать?", text: $text)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(commit)
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))

                    HStack(spacing: 8) {
                        quick("Сегодня", Date().startOfDay)
                        Spacer(minLength: 0)
                        DatePicker("Дата", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                    }

                    if editing == nil {
                        repeatCard
                    } else if editing?.seriesID != nil {
                        Label("Повторяющаяся задача — изменения касаются только этого дня",
                              systemImage: "repeat")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: commit) {
                        Label(editing == nil ? "Добавить" : "Сохранить",
                              systemImage: editing == nil ? "plus" : "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!canCommit)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing == nil ? "Новая задача" : "Изменить задачу")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(340), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: repeatOn) { _, on in
            if on { weekdays = [date.weekday] }
            detent = on ? .large : .height(340)
        }
        .onAppear { focused = true }
    }

    private var repeatCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $repeatOn.animation(.snappy)) {
                Label("Повторять по дням", systemImage: "repeat")
            }

            if repeatOn {
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

                HStack(spacing: 8) {
                    Button("Каждый день") { weekdays = Set(1...7) }
                    Button("Будни") { weekdays = [2, 3, 4, 5, 6] }
                    Button("Выходные") { weekdays = [1, 7] }
                    Spacer(minLength: 0)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Toggle("Закончить повторы", isOn: $limitOn.animation(.snappy))
                if limitOn {
                    DatePicker("До", selection: $until, in: date..., displayedComponents: .date)
                }

                if weekdays.isEmpty {
                    Text("Выберите хотя бы один день")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func quick(_ title: String, _ day: Date) -> some View {
        let on = cal.isDate(date, inSameDayAs: day)
        return Button(title) { date = day }
            .buttonStyle(.bordered)
            .tint(on ? brand : Color.secondary)
            .controlSize(.small)
    }

    private func commit() {
        guard canCommit else { return }
        if let editing {
            store.updateTodo(editing, title: trimmed, date: date)
        } else if repeatOn {
            store.addRepeating(trimmed, from: date, weekdays: weekdays, until: limitOn ? until : nil)
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
            .navigationTitle(String(year))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if year != cal.component(.year, from: Date()) {
                        Button("Сегодня") {
                            year = cal.component(.year, from: Date())
                        }
                    }
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

    private static let rowHeight: CGFloat = 78

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
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

        VStack(alignment: .leading, spacing: 8) {
            Text(Fmt.string(first, "LLLL").capFirst)
                .font(.title2.bold())
                .foregroundStyle(isCurrentMonth ? brand : Color.primary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(weekdayOrder, id: \.self) { wd in
                    Text(shortWeekday(wd))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // один ForEach с уникальными id: отрицательные — пустые клетки до 1-го числа
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(-offset..<count, id: \.self) { i in
                    if i < 0 {
                        Color.clear.frame(height: Self.rowHeight)
                    } else {
                        let date = cal.date(from: DateComponents(year: year, month: month, day: i + 1)) ?? first
                        DayCell(date: date, height: Self.rowHeight) { onSelect(date) }
                    }
                }
            }
        }
    }
}

struct DayCell: View {
    @EnvironmentObject private var store: Store
    @Environment(\.brand) private var brand
    let date: Date
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        let todos = store.todos(on: date)
        let isToday = cal.isDateInToday(date)
        let weekend = date.weekday == 1 || date.weekday == 7
        let shown = todos.count > 3 ? 2 : todos.count
        let extra = todos.count - shown

        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isToday ? Color.white : (weekend ? Color.secondary : Color.primary))
                    .frame(width: 22, height: 22)
                    .background {
                        if isToday { Circle().fill(brand) }
                    }

                VStack(alignment: .leading, spacing: 1.5) {
                    ForEach(todos.prefix(shown)) { t in
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
                    if extra > 0 {
                        Text("+\(extra)")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            .padding(.horizontal, 2)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
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
    @State private var showImporter = false
    @State private var pendingImport: Data?
    @State private var importMessage: String?

    // Тело разбито на части: одним выражением компилятор его не проверяет за разумное время

    var body: some View {
        NavigationStack {
            withDialogs(withSyncHandlers(form))
        }
    }

    private var form: some View {
        Form {
            appearanceSection
            AISettingsSection()
            remindersSection
            dataSection
            backupSection
            Section {
                LabeledContent("Версия", value: "2.0")
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }

    private var appearanceSection: some View {
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
                        accentSwatch(i)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func accentSwatch(_ i: Int) -> some View {
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

    private var remindersSection: some View {
        Section {
            Toggle("Задачи в Напоминаниях", isOn: $remTasks)
            if remTasks {
                listPicker
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
    }

    private var listPicker: some View {
        Picker("Список", selection: $remListID) {
            if remListID.isEmpty {
                Text("Распорядок дня").tag("")
            }
            ForEach(lists) { l in
                Text(l.title).tag(l.id)
            }
        }
    }

    private var dataSection: some View {
        Section("Данные") {
            NavigationLink {
                ClearDatesView()
            } label: {
                Label("Очистить дела по датам", systemImage: "calendar.badge.minus")
            }
            Button("Удалить выполненные задачи") { store.clearCompleted() }
            Button("Сбросить всё", role: .destructive) { showReset = true }
        }
    }

    private var backupSection: some View {
        Section {
            ShareLink(item: backupURL()) {
                Label("Экспортировать копию", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("Восстановить из копии", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Резервная копия")
        } footer: {
            Text("Копия — это JSON-файл со всем распорядком и задачами. Сохраните его в «Файлы» или отправьте себе.")
        }
    }

    private func withSyncHandlers<V: View>(_ content: V) -> some View {
        content
            .onAppear(perform: loadLists)
            .onChange(of: remTasks) { _, on in
                Task { await tasksChanged(on) }
            }
            .onChange(of: remRoutine) { _, on in
                Task { await routineChanged(on) }
            }
            .onChange(of: remListID) { _, _ in
                Task { await store.taskListChanged() }
            }
            .alert("Нет доступа к Напоминаниям", isPresented: $showDenied) {
                Button("Открыть настройки") { openSystemSettings() }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Разрешите доступ: Настройки → Приложения → Распорядок → Напоминания.")
            }
    }

    private func withDialogs<V: View>(_ content: V) -> some View {
        content
            .confirmationDialog(
                "Удалить все задачи и весь распорядок?",
                isPresented: $showReset,
                titleVisibility: .visible
            ) {
                Button("Сбросить", role: .destructive) { store.resetAll() }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType.json]) { result in
                handlePicked(result)
            }
            .confirmationDialog(
                "Заменить все текущие данные содержимым копии?",
                isPresented: importPending,
                titleVisibility: .visible
            ) {
                Button("Восстановить", role: .destructive) { runImport() }
            }
            .alert(importMessage ?? "", isPresented: messageShown) {
                Button("OK", role: .cancel) {}
            }
    }

    private var importPending: Binding<Bool> {
        Binding<Bool>(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        )
    }

    private var messageShown: Binding<Bool> {
        Binding<Bool>(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func handlePicked(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) {
            pendingImport = data
        } else {
            importMessage = "Не удалось прочитать файл."
        }
    }

    private func runImport() {
        guard let data = pendingImport else { return }
        pendingImport = nil
        Task {
            let ok = await store.importData(data)
            importMessage = ok ? "Данные восстановлены." : "Файл не похож на копию «Распорядка»."
        }
    }

    /// Пишет копию во временный файл и возвращает его адрес (для ShareLink)
    private func backupURL() -> URL {
        let name = "Распорядок-\(dayKey(Date())).json"
        let url = URL.temporaryDirectory.appending(path: name)
        try? store.exportData().write(to: url, options: .atomic)
        return url
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

// MARK: - Очистка дел на выбранных датах

struct ClearDatesView: View {
    @EnvironmentObject private var store: Store
    @State private var selection: Set<DateComponents> = []
    @State private var confirm = false

    private var dates: [Date] {
        selection.compactMap { c in
            guard let y = c.year, let m = c.month, let d = c.day else { return nil }
            return cal.date(from: DateComponents(year: y, month: m, day: d))
        }
    }

    var body: some View {
        let days = dates
        let count = store.todoCount(on: days)

        Form {
            Section {
                MultiDatePicker("Даты", selection: $selection)
            } footer: {
                if days.isEmpty {
                    Text("Отметьте даты, на которые нужно удалить все дела.")
                } else {
                    Text("Выбрано дат: \(days.count) · дел: \(count)")
                }
            }

            Section {
                Button("Очистить выбранные даты", role: .destructive) {
                    confirm = true
                }
                .disabled(days.isEmpty || count == 0)
            }
        }
        .navigationTitle("Очистка дел")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Удалить дел: \(count)?",
            isPresented: $confirm,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                store.clearTodos(on: days)
                selection = []
            }
        }
    }
}

// MARK: - ИИ-помощник: ключ и настройки
//
// Запросы идут в OpenRouter (https://openrouter.ai) — один ключ даёт доступ к разным моделям.
// Ключ хранится в Связке ключей, модель — в UserDefaults.

enum AIConfig {
    static let keyName = "openrouterKey"
    static let defaultModel = "openrouter/auto"

    static var apiKey: String { Keychain.get(keyName) ?? "" }
}

enum Keychain {
    private static let service = "DayPlanner"

    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Пустая строка — удалить значение
    static func set(_ value: String, for key: String) {
        SecItemDelete(query(key) as CFDictionary)
        guard !value.isEmpty else { return }
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// Секция с ключом OpenRouter и моделью (в Настройках и в окне чата)
struct AISettingsSection: View {
    @AppStorage("aiModel") private var model = AIConfig.defaultModel
    @State private var key = AIConfig.apiKey
    private let onKeyChange: ((String) -> Void)?

    init(onKeyChange: ((String) -> Void)? = nil) {
        self.onKeyChange = onKeyChange
    }

    var body: some View {
        Section {
            SecureField("Ключ OpenRouter (sk-or-…)", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: key) { _, new in
                    let clean = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    Keychain.set(clean, for: AIConfig.keyName)
                    onKeyChange?(clean)
                }
            LabeledContent("Модель") {
                TextField(AIConfig.defaultModel, text: $model)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if let keys = URL(string: "https://openrouter.ai/keys") {
                Link(destination: keys) {
                    Label("Получить ключ", systemImage: "key")
                }
            }
            if let models = URL(string: "https://openrouter.ai/models") {
                Link(destination: models) {
                    Label("Список моделей", systemImage: "list.bullet")
                }
            }
        } header: {
            Text("ИИ-помощник (OpenRouter)")
        } footer: {
            Text("Ключ хранится в Связке ключей только на этом устройстве. Модель — идентификатор с сайта OpenRouter, например openrouter/auto или google/gemini-2.5-flash.")
        }
    }
}

// MARK: - ИИ-помощник: запрос к OpenRouter

struct ChatMessage: Codable, Sendable {
    let role: String      // system / user / assistant
    let content: String
}

enum AIError: LocalizedError {
    case noKey
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "Добавьте ключ OpenRouter."
        case .http(401, _):
            return "Ключ OpenRouter не подошёл. Проверьте его в настройках."
        case .http(402, _):
            return "На счёте OpenRouter закончились средства."
        case .http(429, _):
            return "Слишком много запросов. Подождите немного и повторите."
        case .http(let code, let message):
            let text = message.isEmpty ? "неизвестная ошибка" : message
            return "Ошибка OpenRouter (\(code)): \(text)"
        case .empty:
            return "Модель вернула пустой ответ. Попробуйте ещё раз или выберите другую модель."
        }
    }
}

enum OpenRouter {
    private struct Body: Encodable {
        let model: String
        let messages: [ChatMessage]
    }

    private struct Reply: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        struct Failure: Decodable { let message: String? }
        let choices: [Choice]?
        let error: Failure?
    }

    static func complete(model: String, key: String, messages: [ChatMessage]) async throws -> String {
        guard !key.isEmpty else { throw AIError.noKey }
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { throw AIError.empty }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://github.com/GARCIERcas/DayPlanner2", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("DayPlanner", forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONEncoder().encode(Body(model: model, messages: messages))

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let reply = try? JSONDecoder().decode(Reply.self, from: data)

        // OpenRouter иногда присылает ошибку и с кодом 200
        if code != 200 || reply?.error != nil {
            let message = reply?.error?.message ?? String(data: data, encoding: .utf8) ?? ""
            throw AIError.http(code, message)
        }
        guard let text = reply?.choices?.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.empty
        }
        return text
    }
}

// MARK: - ИИ-помощник: промпт и разбор ответа

struct TodoDraft: Hashable {
    let title: String
    let date: Date
}

/// Что предложил ИИ: пункты распорядка и разовые задачи
struct AIPlan {
    var reply: String
    var items: [ScheduleItem]
    var replace: Bool
    var todos: [TodoDraft]

    var isEmpty: Bool { items.isEmpty && todos.isEmpty }
}

enum AIPlanParser {
    private struct Raw: Decodable {
        struct Item: Decodable {
            let title: String
            let kind: String?
            let start: String
            let end: String?
            let days: [String]?
        }
        struct Todo: Decodable {
            let title: String
            let date: String
        }
        let reply: String?
        let replace: Bool?
        let schedule: [Item]?
        let todos: [Todo]?
    }

    private static let dayCodes = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]

    static func isoFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// «07:30» → 450
    private static func minutes(_ s: String) -> Int? {
        let parts = s.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 2, (0...24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return (parts[0] * 60 + parts[1]) % 1440
    }

    static func parse(_ text: String) -> AIPlan {
        // модель могла обернуть JSON в ```json … ``` или добавить текст вокруг — берём сам объект
        guard let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}"), s < e,
              let raw = try? JSONDecoder().decode(Raw.self, from: Data(String(text[s...e]).utf8)) else {
            return AIPlan(reply: text, items: [], replace: false, todos: [])
        }

        let items: [ScheduleItem] = (raw.schedule ?? []).compactMap { r in
            guard let start = minutes(r.start) else { return nil }
            let duration = r.end.flatMap(minutes).map { ($0 - start + 1440) % 1440 } ?? 0
            var days = Set((r.days ?? []).compactMap { dayCodes[String($0.lowercased().prefix(3))] })
            if days.isEmpty { days = Set(1...7) }
            let kind = RoutineKind(rawValue: (r.kind ?? "").lowercased()) ?? .other
            let title = r.title.trimmingCharacters(in: .whitespaces)
            return ScheduleItem(
                title: title.isEmpty ? kind.title : title,
                kind: kind, start: start, duration: duration, weekdays: days
            )
        }

        let f = isoFormatter()
        let todos: [TodoDraft] = (raw.todos ?? []).compactMap { t in
            let title = t.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, let d = f.date(from: t.date) else { return nil }
            return TodoDraft(title: title, date: d.startOfDay)
        }

        return AIPlan(reply: raw.reply ?? "", items: items, replace: raw.replace ?? false, todos: todos)
    }
}

@MainActor
enum AIPrompt {
    static func system(store: Store) -> String {
        let today = Date().startOfDay
        let iso = AIPlanParser.isoFormatter()

        let routine = weekdayOrder.map { wd -> String in
            let items = store.items(forWeekday: wd).map { item -> String in
                let time = Fmt.time(item.start) + (item.duration > 0 ? "–" + Fmt.time(item.end) : "")
                return "\(time) \(item.title) [\(item.kind.rawValue)]"
            }
            return "\(shortWeekday(wd)): " + (items.isEmpty ? "пусто" : items.joined(separator: "; "))
        }.joined(separator: "\n")

        let upcoming = (0..<7).flatMap { i -> [String] in
            let day = today.addingDays(i)
            return store.todos(on: day).filter { !$0.isDone }.map { "\(iso.string(from: day)): \($0.title)" }
        }

        return """
        Ты — ИИ-помощник в iOS-приложении «Распорядок дня». Пользователь пишет, как хочет построить свой день или неделю, а ты составляешь для него расписание. Общайся по-русски, дружелюбно и коротко.

        Сегодня: \(iso.string(from: today)) (\(Fmt.string(today, "EEEE"))).

        Текущий распорядок по дням недели:
        \(routine)

        Невыполненные задачи на ближайшую неделю:
        \(upcoming.isEmpty ? "нет" : upcoming.joined(separator: "\n"))

        Отвечай ТОЛЬКО одним JSON-объектом, без markdown и текста вокруг:
        {
          "reply": "короткий ответ пользователю",
          "replace": false,
          "schedule": [
            {"title": "Завтрак", "kind": "meal", "start": "08:00", "end": "08:30", "days": ["mon", "tue", "wed", "thu", "fri"]}
          ],
          "todos": [
            {"title": "Купить продукты", "date": "YYYY-MM-DD"}
          ]
        }

        Правила:
        - schedule — повторяющийся распорядок. days: mon, tue, wed, thu, fri, sat, sun.
        - kind — одно из: wake (подъём), meal (еда), sport, work (работа/учёба), free (отдых), sleep (сон), other.
        - start и end — время "HH:mm". Для мгновенных событий (подъём) end = null. Если пункт идёт за полночь (сон), end меньше start — это нормально.
        - replace = true, когда пользователь просит составить распорядок заново: тогда все старые пункты на днях из твоего schedule будут удалены, поэтому присылай полный распорядок на эти дни. replace = false — твои пункты просто добавятся к текущим, не повторяй уже существующие.
        - Пункты распорядка не должны пересекаться по времени.
        - todos — разовые дела на конкретные даты (дата в формате YYYY-MM-DD). Если дата не названа — ставь сегодняшнюю.
        - Если не хватает информации или пользователь просто задаёт вопрос — оставь schedule и todos пустыми и спроси/ответь в reply.
        - В reply кратко опиши, что предлагаешь. Не перечисляй там все пункты — приложение само покажет их карточкой.
        """
    }
}

// MARK: - ИИ-помощник: переписка

struct AIChatMessage: Identifiable {
    let id = UUID()
    let role: String      // user / assistant
    let raw: String       // текст, который уходит в историю для модели
    var text: String      // что показываем
    var plan: AIPlan?
    var applied = false
}

@MainActor
final class AIChat: ObservableObject {
    @Published var messages: [AIChatMessage] = []
    @Published var loading = false
    @Published var error: String?

    func send(_ text: String, store: Store, model: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !loading else { return }

        messages.append(AIChatMessage(role: "user", raw: clean, text: clean))
        loading = true
        error = nil
        defer { loading = false }

        let history = [ChatMessage(role: "system", content: AIPrompt.system(store: store))]
            + messages.suffix(20).map { ChatMessage(role: $0.role, content: $0.raw) }
        let modelID = model.trimmingCharacters(in: .whitespaces).isEmpty
            ? AIConfig.defaultModel
            : model.trimmingCharacters(in: .whitespaces)

        do {
            let answer = try await OpenRouter.complete(model: modelID, key: AIConfig.apiKey, messages: history)
            let plan = AIPlanParser.parse(answer)
            messages.append(AIChatMessage(
                role: "assistant",
                raw: answer,
                text: plan.reply,
                plan: plan.isEmpty ? nil : plan
            ))
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Переносит предложение ИИ в распорядок и задачи
    func apply(_ id: UUID, store: Store) {
        guard let i = messages.firstIndex(where: { $0.id == id }),
              let plan = messages[i].plan, !messages[i].applied else { return }

        if plan.replace {
            let days = Set(plan.items.flatMap(\.weekdays))
            for wd in days {
                for old in store.items(forWeekday: wd) {
                    store.remove(old, fromWeekday: wd)
                }
            }
        }
        for item in plan.items { store.upsert(item) }
        for t in plan.todos { store.addTodo(t.title, on: t.date) }
        messages[i].applied = true
    }

    func clear() {
        messages = []
        error = nil
    }
}

// MARK: - ИИ-помощник: окно чата

struct AIChatView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var brand
    @AppStorage("aiModel") private var model = AIConfig.defaultModel
    @ObservedObject var chat: AIChat

    @State private var input = ""
    @State private var hasKey = !AIConfig.apiKey.isEmpty
    @State private var showSettings = false
    @FocusState private var focused: Bool

    private let examples = [
        "Составь распорядок на будни: работаю с 9 до 18, хочу спорт 3 раза в неделю и ложиться в 23:00",
        "Добавь пробежку по утрам в выходные",
        "Распланируй дела на завтра: купить продукты, позвонить маме, сдать отчёт"
    ]

    var body: some View {
        NavigationStack {
            Group {
                if hasKey {
                    conversation
                } else {
                    AIKeySetup { hasKey = true }
                }
            }
            .navigationTitle("ИИ-помощник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Ключ и модель", systemImage: "key")
                        }
                        Button(role: .destructive) {
                            withAnimation { chat.clear() }
                        } label: {
                            Label("Очистить чат", systemImage: "trash")
                        }
                        .disabled(chat.messages.isEmpty)
                    } label: {
                        Label("Ещё", systemImage: "ellipsis")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { hasKey = !AIConfig.apiKey.isEmpty }) {
            NavigationStack {
                Form { AISettingsSection() }
                    .navigationTitle("ИИ-помощник")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Готово") { showSettings = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if chat.messages.isEmpty {
                            welcome
                        }
                        ForEach(chat.messages) { m in
                            bubble(m).id(m.id)
                        }
                        if chat.loading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Составляю расписание…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .id("loading")
                        }
                        if let error = chat.error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("error")
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
                .onChange(of: chat.loading) { _, on in
                    if on { withAnimation { proxy.scrollTo("loading", anchor: .bottom) } }
                }
            }

            inputBar
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Опишите, каким должен быть ваш день — я составлю распорядок и список дел.",
                  systemImage: "sparkles")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(examples, id: \.self) { example in
                Button {
                    input = example
                    focused = true
                } label: {
                    Text(example)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(brand.opacity(0.12), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func bubble(_ m: AIChatMessage) -> some View {
        if m.role == "user" {
            HStack {
                Spacer(minLength: 40)
                Text(m.text)
                    .padding(12)
                    .foregroundStyle(.white)
                    .background(brand, in: .rect(cornerRadius: 18))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !m.text.isEmpty {
                    Text(m.text)
                }
                if let plan = m.plan {
                    AIPlanCard(plan: plan, applied: m.applied) {
                        withAnimation { chat.apply(m.id, store: store) }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Напишите, что запланировать…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.loading)
            .accessibilityLabel("Отправить")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func send() {
        let text = input
        input = ""
        Task { await chat.send(text, store: store, model: model) }
    }
}

/// Первый запуск чата: просим ввести ключ OpenRouter
struct AIKeySetup: View {
    let onReady: () -> Void
    @State private var filled = !AIConfig.apiKey.isEmpty

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                    Text("Подключите ИИ")
                        .font(.title3.weight(.semibold))
                    Text("Вставьте ключ OpenRouter — и помощник сможет составлять распорядок и задачи по вашему сообщению.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            AISettingsSection { filled = !$0.isEmpty }

            Section {
                Button("Продолжить", action: onReady)
                    .frame(maxWidth: .infinity)
                    .disabled(!filled)
            }
        }
    }
}

/// Карточка с предложением ИИ и кнопкой «Применить»
struct AIPlanCard: View {
    let plan: AIPlan
    let applied: Bool
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !plan.items.isEmpty {
                Label(plan.replace ? "Новый распорядок" : "В распорядок", systemImage: "clock")
                    .font(.subheadline.weight(.semibold))
                ForEach(plan.items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.displayIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(item.displayColor.gradient, in: .circle)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.callout.weight(.medium))
                            Text(timeText(item) + " · " + daysText(item.weekdays))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !plan.todos.isEmpty {
                Label("Задачи", systemImage: "checklist")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, plan.items.isEmpty ? 0 : 4)
                ForEach(plan.todos, id: \.self) { t in
                    HStack(spacing: 10) {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                        Text(t.title)
                            .font(.callout)
                        Spacer(minLength: 0)
                        Text(Fmt.string(t.date, "d MMM"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if plan.replace && !plan.items.isEmpty && !applied {
                Label("Старые пункты на эти дни будут заменены", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button(action: onApply) {
                Label(applied ? "Добавлено" : "Применить",
                      systemImage: applied ? "checkmark" : "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(applied)
        }
    }

    private func timeText(_ item: ScheduleItem) -> String {
        item.duration > 0 ? Fmt.time(item.start) + "–" + Fmt.time(item.end) : Fmt.time(item.start)
    }

    private func daysText(_ days: Set<Int>) -> String {
        if days.count == 7 { return "каждый день" }
        if days == [2, 3, 4, 5, 6] { return "будни" }
        if days == [1, 7] { return "выходные" }
        return weekdayOrder.filter { days.contains($0) }.map(shortWeekday).joined(separator: ", ")
    }
}
