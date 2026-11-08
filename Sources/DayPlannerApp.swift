//
//  DayPlannerApp.swift
//  Распорядок дня + To-Do  (v2.0 MVP)
//
//  Требования: Xcode 26+, iOS 26.0+ (Liquid Glass).
//  MVP: распорядок по дням недели + задачи на день, хранение в JSON.
//  Данные из v1.x (planner.json) подхватываются автоматически.
//

import SwiftUI

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

// MARK: - Тема и акцент

enum Palette {
    static let colors: [Color] = [.blue, .indigo, .purple, .pink, .orange, .green, .teal]

    static func color(_ i: Int) -> Color {
        colors.indices.contains(i) ? colors[i] : .blue
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
    /// Григорианский календарь, неделя с понедельника
    static let planner: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()
}

private let cal = Calendar.planner

/// Порядок дней недели (Calendar.weekday: 1 = Вс, 2 = Пн … 7 = Сб)
let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

func shortWeekday(_ wd: Int) -> String {
    ["", "Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"][wd]
}

func durationText(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
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
    var isToday: Bool { cal.isDateInToday(self) }

    func addingDays(_ n: Int) -> Date {
        cal.date(byAdding: .day, value: n, to: self) ?? self
    }

    var weekStart: Date {
        cal.dateInterval(of: .weekOfYear, for: self)?.start ?? startOfDay
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
        case .wake: .orange
        case .meal: .green
        case .sport: .red
        case .work: .blue
        case .free: .purple
        case .sleep: .indigo
        case .other: .gray
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

    var end: Int { start + duration }

    /// До какой минуты пункт считается «текущим» (без длительности — 5 минут)
    var activeEnd: Int { duration > 0 ? end : start + 5 }
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var isDone = false
}

// MARK: - Хранилище (JSON в Documents)

@MainActor
final class Store: ObservableObject {
    @Published private(set) var schedule: [ScheduleItem] = []
    @Published private(set) var todos: [TodoItem] = []

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
        }
    }

    // Распорядок

    func items(forWeekday wd: Int) -> [ScheduleItem] {
        schedule.filter { $0.weekdays.contains(wd) }.sorted { $0.start < $1.start }
    }

    func upsert(_ item: ScheduleItem) {
        if let i = schedule.firstIndex(where: { $0.id == item.id }) {
            schedule[i] = item
        } else {
            schedule.append(item)
        }
        save()
    }

    /// Убирает пункт только из одного дня недели
    func remove(_ item: ScheduleItem, fromWeekday wd: Int) {
        guard let i = schedule.firstIndex(where: { $0.id == item.id }) else { return }
        schedule[i].weekdays.remove(wd)
        if schedule[i].weekdays.isEmpty { schedule.remove(at: i) }
        save()
    }

    func removeEverywhere(_ item: ScheduleItem) {
        schedule.removeAll { $0.id == item.id }
        save()
    }

    // Задачи (невыполненные сверху)

    func todos(on date: Date) -> [TodoItem] {
        let all = todos.filter { cal.isDate($0.date, inSameDayAs: date) }
        return all.filter { !$0.isDone } + all.filter(\.isDone)
    }

    func hasOpenTodos(on date: Date) -> Bool {
        todos.contains { !$0.isDone && cal.isDate($0.date, inSameDayAs: date) }
    }

    func addTodo(_ title: String, on date: Date) {
        todos.append(TodoItem(title: title, date: date.startOfDay))
        save()
    }

    func rename(_ todo: TodoItem, to title: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].title = t
        save()
    }

    func move(_ todo: TodoItem, to date: Date) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].date = date.startOfDay
        save()
    }

    func toggle(_ todo: TodoItem) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].isDone.toggle()
        save()
    }

    func delete(_ todo: TodoItem) {
        todos.removeAll { $0.id == todo.id }
        save()
    }

    func clearCompleted() {
        todos.removeAll(where: \.isDone)
        save()
    }

    func resetAll() {
        todos = []
        schedule = []
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(Snapshot(schedule: schedule, todos: todos))
            try data.write(to: url, options: .atomic)
        } catch {
            print("Save error:", error)
        }
    }
}

// MARK: - Корневой экран

struct RootView: View {
    @State private var tab = 0
    /// Общая выбранная дата для обеих вкладок
    @State private var date = Date().startOfDay

    var body: some View {
        TabView(selection: $tab) {
            Tab("Распорядок", systemImage: "clock", value: 0) {
                ScheduleTab(date: $date)
            }
            Tab("Задачи", systemImage: "checklist", value: 1) {
                TodoTab(date: $date)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: tab)
    }
}

// MARK: - Общие элементы

/// Заголовок в центре панели: месяц и день недели
struct DayTitle: View {
    let date: Date

    var body: some View {
        VStack(spacing: 1) {
            Text(Fmt.string(date, "LLLL").capFirst)
                .font(.headline)
            Text(date.isToday ? "Сегодня, \(Fmt.string(date, "d MMMM"))" : Fmt.string(date, "EEEE, d MMMM").capFirst)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Стандартная панель: настройки слева, «Сегодня» и «+» справа
struct PlannerToolbar: ToolbarContent {
    @Binding var date: Date
    let addLabel: String
    let onAdd: () -> Void
    @Binding var showSettings: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: {
                Label("Настройки", systemImage: "gearshape")
            }
        }
        ToolbarItem(placement: .principal) {
            DayTitle(date: date)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !date.isToday {
                Button {
                    withAnimation(.snappy) { date = Date().startOfDay }
                } label: {
                    Label("Сегодня", systemImage: "arrow.uturn.backward")
                }
            }
            Button(action: onAdd) {
                Label(addLabel, systemImage: "plus")
            }
        }
    }
}

struct KindIcon: View {
    let kind: RoutineKind
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: kind.icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(kind.color.gradient, in: .circle)
    }
}

/// Выбор дней недели + быстрые наборы
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    @Environment(\.brand) private var brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(weekdayOrder, id: \.self) { wd in
                    let on = selection.contains(wd)
                    Button {
                        if on { selection.remove(wd) } else { selection.insert(wd) }
                    } label: {
                        Text(shortWeekday(wd))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? brand : Color.secondary.opacity(0.15), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Button("Каждый день") { selection = Set(1...7) }
                Button("Будни") { selection = [2, 3, 4, 5, 6] }
                Button("Выходные") { selection = [1, 7] }
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Полоса недели

struct WeekStrip: View {
    @Binding var date: Date
    /// Отметить день точкой (например, есть невыполненные задачи)
    var marked: (Date) -> Bool
    @Environment(\.brand) private var brand
    @State private var weekIndex: Int?

    private static let base = Date().weekStart
    private static let range = -156...156   // ±3 года

    init(date: Binding<Date>, marked: @escaping (Date) -> Bool = { _ in false }) {
        _date = date
        self.marked = marked
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
                    weekRow(i).containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $weekIndex, anchor: .leading)
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: weekIndex)
        .onChange(of: weekIndex) { _, new in
            // пролистали неделю — тот же день недели в новой неделе
            guard let new, new != Self.index(of: date) else { return }
            let offset = (date.weekday - cal.firstWeekday + 7) % 7
            date = Self.start(of: new).addingDays(offset)
        }
        .onChange(of: date) { _, new in
            let i = Self.index(of: new)
            if weekIndex != i {
                withAnimation(.snappy) { weekIndex = i }
            }
        }
    }

    private func weekRow(_ i: Int) -> some View {
        let start = Self.start(of: i)
        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { k in
                dayCell(start.addingDays(k))
            }
        }
        .padding(.horizontal, 12)
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = cal.isDate(day, inSameDayAs: date)
        let today = day.isToday
        let dot = marked(day)

        return Button {
            withAnimation(.snappy) { date = day.startOfDay }
        } label: {
            VStack(spacing: 4) {
                Text(Fmt.string(day, "EEEEEE").capFirst)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                Text("\(cal.component(.day, from: day))")
                    .font(.title3.weight(today || selected ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(selected ? Color.white : (today ? brand : Color.primary))
                Circle()
                    .fill(selected ? Color.white : brand)
                    .frame(width: 5, height: 5)
                    .opacity(dot ? 1 : 0)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(brand.gradient)
                } else if today {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(brand.opacity(0.5), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Вкладка «Распорядок»

struct EditorTarget: Identifiable {
    let id = UUID()
    var item: ScheduleItem?
    var weekday: Int
}

enum RowState { case past, now, upcoming }

struct ScheduleTab: View {
    @EnvironmentObject private var store: Store
    @Binding var date: Date
    @State private var editor: EditorTarget?
    @State private var showSettings = false

    var body: some View {
        let items = store.items(forWeekday: date.weekday)

        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(date: $date)

                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    let minute = ctx.date.minutesOfDay
                    let isToday = date.isToday
                    let current = isToday ? items.last(where: { $0.start <= minute && minute < $0.activeEnd }) : nil
                    let next = isToday ? items.first(where: { $0.start > minute }) : nil

                    List {
                        if current != nil || next != nil {
                            NowCard(current: current, next: next, minute: minute)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        }

                        ForEach(items) { item in
                            Button {
                                editor = EditorTarget(item: item, weekday: date.weekday)
                            } label: {
                                TimelineRow(item: item, state: state(of: item, today: isToday, minute: minute, current: current))
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation { store.remove(item, fromWeekday: date.weekday) }
                                } label: {
                                    Label("Убрать", systemImage: "calendar.badge.minus")
                                }
                            }
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
                    }
                    .listStyle(.plain)
                    .overlay {
                        if items.isEmpty {
                            ContentUnavailableView {
                                Label("Распорядок пуст", systemImage: "clock")
                            } description: {
                                Text("Добавьте первый пункт на \(Fmt.string(date, "EEEE"))")
                            } actions: {
                                Button("Добавить пункт") { add() }
                                    .buttonStyle(.glassProminent)
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlannerToolbar(date: $date, addLabel: "Новый пункт", onAdd: add, showSettings: $showSettings)
            }
        }
        .sheet(item: $editor) { target in
            ScheduleEditor(item: target.item, weekday: target.weekday)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func add() {
        editor = EditorTarget(item: nil, weekday: date.weekday)
    }

    private func state(of item: ScheduleItem, today: Bool, minute: Int, current: ScheduleItem?) -> RowState {
        guard today else { return .upcoming }
        if item.id == current?.id { return .now }
        return item.activeEnd <= minute ? .past : .upcoming
    }
}

/// Карточка «Сейчас / Далее» — только для сегодняшнего дня
struct NowCard: View {
    let current: ScheduleItem?
    let next: ScheduleItem?
    let minute: Int

    private var tint: Color { (current ?? next)?.kind.color ?? .gray }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let c = current {
                HStack(spacing: 12) {
                    KindIcon(kind: c.kind, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("СЕЙЧАС")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(c.kind.color)
                        Text(c.title)
                            .font(.title3.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                    Text(Fmt.time(c.start))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if c.duration > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(min(max(0, minute - c.start), c.duration)),
                                     total: Double(c.duration))
                            .tint(c.kind.color)
                        Text("Осталось \(durationText(max(1, c.end - minute))) · до \(Fmt.time(c.end))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let n = next {
                if current != nil { Divider() }
                HStack(spacing: 10) {
                    Image(systemName: n.kind.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(n.kind.color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Далее")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(n.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.time(n.start))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        Text("через \(durationText(n.start - minute))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 22, style: .continuous))
    }
}

/// Строка распорядка: время · иконка · название. Прошедшие — приглушены.
struct TimelineRow: View {
    let item: ScheduleItem
    let state: RowState

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.time(item.start))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if item.duration > 0 {
                    Text(Fmt.time(item.end))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, alignment: .leading)

            KindIcon(kind: item.kind)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .strikethrough(state == .past, color: .secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if state == .now {
                Circle()
                    .fill(item.kind.color)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if state == .now {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(item.kind.color.opacity(0.1))
            }
        }
        .opacity(state == .past ? 0.45 : 1)
        .contentShape(Rectangle())
    }

    private var subtitle: String? {
        let sameAsKind = item.title == item.kind.title
        if item.duration > 0 {
            return sameAsKind ? durationText(item.duration) : "\(item.kind.title) · \(durationText(item.duration))"
        }
        return sameAsKind ? nil : item.kind.title
    }
}

// MARK: - Редактор пункта распорядка

struct ScheduleEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private let original: ScheduleItem?
    private let weekday: Int
    @State private var title: String
    @State private var kind: RoutineKind
    @State private var time: Date
    @State private var duration: Int
    @State private var weekdays: Set<Int>

    init(item: ScheduleItem?, weekday: Int) {
        original = item
        self.weekday = weekday
        _title = State(initialValue: item?.title ?? "")
        _kind = State(initialValue: item?.kind ?? .other)
        _time = State(initialValue: Self.date(fromMinutes: item?.start ?? 9 * 60))
        _duration = State(initialValue: item?.duration ?? 0)
        _weekdays = State(initialValue: item?.weekdays ?? [weekday])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        KindIcon(kind: kind)
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
                    Toggle("Окончание", isOn: hasEnd.animation(.snappy))
                    if duration > 0 {
                        DatePicker("Конец", selection: endTime, displayedComponents: .hourAndMinute)
                        LabeledContent("Длительность", value: durationText(duration))
                    }
                }

                Section {
                    WeekdayPicker(selection: $weekdays)
                } header: {
                    Text("Повторять")
                } footer: {
                    if weekdays.isEmpty {
                        Text("Выберите хотя бы один день").foregroundStyle(.red)
                    }
                }

                if let original {
                    Section {
                        if original.weekdays.count > 1 {
                            Button("Убрать только из этого дня", role: .destructive) {
                                store.remove(original, fromWeekday: weekday)
                                dismiss()
                            }
                        }
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

    private var hasEnd: Binding<Bool> {
        Binding(get: { duration > 0 }, set: { duration = $0 ? 60 : 0 })
    }

    /// Конец раньше начала — значит, на следующие сутки
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
        var item = original ?? ScheduleItem(title: "", kind: kind, start: 0, duration: 0, weekdays: [])
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

// MARK: - Вкладка «Задачи»

struct TodoTab: View {
    @EnvironmentObject private var store: Store
    @Environment(\.brand) private var brand
    @Binding var date: Date

    @State private var newTitle = ""
    @FocusState private var addFocused: Bool
    @State private var renaming: TodoItem?
    @State private var renameText = ""
    @State private var showSettings = false

    var body: some View {
        let todos = store.todos(on: date)
        let done = todos.filter(\.isDone).count

        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(date: $date) { store.hasOpenTodos(on: $0) }

                List {
                    if !todos.isEmpty {
                        ProgressCard(done: done, total: todos.count)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        ForEach(todos) { todo in
                            TodoRow(todo: todo)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation { store.delete(todo) }
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        withAnimation { store.move(todo, to: todo.date.addingDays(1)) }
                                    } label: {
                                        Label("Завтра", systemImage: "arrow.turn.up.right")
                                    }
                                    .tint(.orange)
                                }
                                .contextMenu {
                                    Button {
                                        renameText = todo.title
                                        renaming = todo
                                    } label: {
                                        Label("Переименовать", systemImage: "pencil")
                                    }
                                    Button {
                                        withAnimation { store.move(todo, to: todo.date.addingDays(1)) }
                                    } label: {
                                        Label("Перенести на завтра", systemImage: "arrow.turn.up.right")
                                    }
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
                            TextField("Новая задача", text: $newTitle)
                                .focused($addFocused)
                                .submitLabel(.done)
                                .onSubmit(add)
                        }
                    } footer: {
                        if todos.isEmpty {
                            Text("На этот день задач нет. Напишите первую выше.")
                        } else {
                            Text("Свайп вправо — перенести на завтра, влево — удалить.")
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlannerToolbar(date: $date, addLabel: "Новая задача",
                               onAdd: { addFocused = true }, showSettings: $showSettings)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("Переименовать", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Название", text: $renameText)
            Button("Сохранить") {
                if let t = renaming { store.rename(t, to: renameText) }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func add() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        withAnimation(.snappy) { store.addTodo(t, on: date) }
        newTitle = ""
        addFocused = true   // можно сразу вводить следующую
    }
}

/// Кольцо прогресса за день
struct ProgressCard: View {
    @Environment(\.brand) private var brand
    let done: Int
    let total: Int

    private var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    private var allDone: Bool { total > 0 && done == total }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(brand.opacity(0.15), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(allDone ? Color.green : brand,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: fraction)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption.weight(.bold).monospacedDigit())
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(allDone ? "Всё сделано!" : "Выполнено \(done) из \(total)")
                    .font(.headline)
                Text(allDone ? "Отличный день" : "Осталось задач: \(total - done)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
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
        .sensoryFeedback(.success, trigger: todo.isDone) { _, new in new }
    }
}

// MARK: - Настройки

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var theme = 0
    @AppStorage("accent") private var accent = 0
    @State private var showReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Внешний вид") {
                    Picker("Тема", selection: $theme) {
                        Text("Системная").tag(0)
                        Text("Светлая").tag(1)
                        Text("Тёмная").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    HStack {
                        ForEach(Palette.colors.indices, id: \.self) { i in
                            Button { accent = i } label: {
                                Circle()
                                    .fill(Palette.colors[i].gradient)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if accent == i {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Данные") {
                    Button("Удалить выполненные задачи") { store.clearCompleted() }
                    Button("Сбросить всё", role: .destructive) { showReset = true }
                }

                Section {
                    LabeledContent("Версия", value: "2.0 MVP")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .confirmationDialog("Удалить все задачи и весь распорядок?",
                                isPresented: $showReset, titleVisibility: .visible) {
                Button("Сбросить", role: .destructive) { store.resetAll() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
