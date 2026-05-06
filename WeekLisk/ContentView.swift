//
//  ContentView.swift
//  WeekLisk
//
//  Created by 魏嘉賢 on 2026/3/29.
//

import SwiftUI
import UserNotifications

// MARK: - Models (資料模型)

/// 代表一個「主目標」
struct Goal: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var subTasks: [SubTask] = [] // 每個目標可以包含多個子任務
}

/// 代表目標下的「子任務」
struct SubTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false // 記錄該任務是否已完成
}

/// 歷史週目標資料結構
struct ArchivedGoals: Identifiable, Codable {
    var id: UUID = UUID()
    var weekOfYear: Int
    var yearForWeek: Int
    var goals: [Goal]
}

// MARK: - UserDefaults persistence (資料持久化擴充)

/// 擴充 Array，當陣列元素是 Goal 時，提供存取 UserDefaults 的功能
extension Array where Element == Goal {
    /// 存在 UserDefaults 的 Key
    static let goalsKey = "weekLisk_goals"

    /// 從 UserDefaults 讀取並解碼目標資料
    static func load() -> [Goal] {
        guard let data = UserDefaults.standard.data(forKey: goalsKey),
              let decoded = try? JSONDecoder().decode([Goal].self, from: data) else {
            return [] // 若無資料或解碼失敗，回傳空陣列
        }
        return decoded
    }

    /// 將目前的目標陣列編碼並儲存到 UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Array.goalsKey)
        }
    }
}

/// 歷史資料 UserDefaults 擴充
extension Array where Element == ArchivedGoals {
    static let archivedGoalsKey = "weekLisk_archivedGoals"

    static func load() -> [ArchivedGoals] {
        guard let data = UserDefaults.standard.data(forKey: archivedGoalsKey),
              let decoded = try? JSONDecoder().decode([ArchivedGoals].self, from: data) else {
            return []
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Array.archivedGoalsKey)
        }
    }
}

// MARK: - ContentView (主視圖)

struct ContentView: View {
    // 狀態變數管理
    @State private var goals: [Goal] = Array.load() // 初始載入儲存的資料
    @State private var archivedGoals: [ArchivedGoals] = Array<ArchivedGoals>.load()
    @State private var showingGoalInput = false // 控制新增目標 Sheet 的顯示
    @State private var draftGoalTitles: [String] = Array(repeating: "", count: 3) // 預設提供 3 個空白目標輸入框
    @FocusState private var focusedGoalIndex: Int? // 新增的 FocusState，改為 Int? 追蹤目前焦點輸入框的索引
    
    // Feed state
    @State private var isFeedPresented: Bool = false
    @State private var dragOffset: CGFloat = 0 // 新增：單純用來記錄手指滑動的距離
    @State private var feedItems: [FeedItem] = []

    @State private var feedVM = FeedViewModel()
    // A simple feed item derived from goals (stub for future API integration)
    struct FeedItem: Identifiable, Codable {
        var id: UUID = UUID()
        var title: String
        var subtitle: String
        var link: URL?
    }

    /// Generate feed items based on current goals. This is a placeholder recommender you can swap with real content later.
    private func refreshFeed() {
        let keywords = goals.map { $0.title }
        var items: [FeedItem] = []
        for key in keywords {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            items.append(FeedItem(title: "Trending: \(trimmed)", subtitle: "Tips, stories, and trends about \(trimmed)", link: nil))
            items.append(FeedItem(title: "How to improve \(trimmed)", subtitle: "Curated guides to help with your weekly goal", link: nil))
        }
        if items.isEmpty {
            items = [FeedItem(title: "Get inspired this week", subtitle: "Add goals to see personalized tips and trends.", link: nil)]
        }
        // Deduplicate by title
        var seen = Set<String>()
        feedItems = items.filter { seen.insert($0.title).inserted }
    }
    
    /// 計算屬性：取得當前年份與週數，用作 UI 顯示 (例如 "Week 13, 2026")
    private var currentWeekTitle: String {
        let calendar = Calendar.current
        let now = Date()
        let weekOfYear = calendar.component(.weekOfYear, from: now)
        let yearForWeek = calendar.component(.yearForWeekOfYear, from: now)
        return "Week \(weekOfYear), \(yearForWeek)"
    }
    private var currentWeekOfYear: Int {
        Calendar.current.component(.weekOfYear, from: Date())
    }
    private var currentYearForWeek: Int {
        Calendar.current.component(.yearForWeekOfYear, from: Date())
    }
    
    private func archiveGoalsIfNeeded() {
        let savedWeek = UserDefaults.standard.integer(forKey: "weekLisk_lastWeekOfYear")
        let savedYear = UserDefaults.standard.integer(forKey: "weekLisk_lastYearForWeek")
        // If savedWeek or savedYear is zero (meaning no saved data), treat as current week/year to avoid archiving empty
        if savedWeek != currentWeekOfYear || savedYear != currentYearForWeek {
            if !goals.isEmpty {
                let archive = ArchivedGoals(
                    weekOfYear: savedWeek == 0 ? currentWeekOfYear : savedWeek,
                    yearForWeek: savedYear == 0 ? currentYearForWeek : savedYear,
                    goals: goals
                )
                archivedGoals.append(archive)
                archivedGoals.save()
            }
            goals = []
            goals.save()
            UserDefaults.standard.set(currentWeekOfYear, forKey: "weekLisk_lastWeekOfYear")
            UserDefaults.standard.set(currentYearForWeek, forKey: "weekLisk_lastYearForWeek")
        }
    }
    
    // 通知權限申請與週通知排程
    private func requestAndScheduleWeeklyNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            scheduleWeeklyReminderNotification()
        }
    }
    
    private func scheduleWeeklyReminderNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekLisk_newGoalsReminder"])
        var dateComponents = DateComponents()
        dateComponents.weekday = 2 // Monday (1=Sunday, 2=Monday,...)
        dateComponents.hour = 9
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "It's a new week!"
        content.body = "Don't forget to enter your new weekly goals."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "weekLisk_newGoalsReminder", content: content, trigger: trigger)
        center.add(request)
    }

    var body: some View {
            ZStack(alignment: .bottom) {
                TabView {
                    goalsTab.tabItem { Label("Goals", systemImage: "target") }
                    checklistTab.tabItem { Label("Checklist", systemImage: "checklist") }
                    historyTab.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                }
                .sheet(isPresented: $showingGoalInput) {
                    goalInputSheet
                }
                
                feedOverlay // 你的底部選單
            }
            // 👇 把舊的 refreshFeed() 刪掉，改成這個：
            .task {
                print("🎯 ZStack 渲染完畢，準備啟動初始 Task")
                await feedVM.fetchPodcasts(for: goals)
            }
            .onChange(of: goals) { _, newGoals in
                print("🎯 偵測到 goals 改變！準備重新 fetch")
                Task {
                    await feedVM.fetchPodcasts(for: newGoals)
                }
            }
        }
    // MARK: - Feed Overlay
        private var feedOverlay: some View {
            let maxHeight: CGFloat = UIScreen.main.bounds.height * 0.85
            let minHeight: CGFloat = 70 // 收合時的高度
            
            let baseHeight = isFeedPresented ? maxHeight : minHeight
            let activeHeight = max(minHeight, min(maxHeight, baseHeight - dragOffset))
            let progress = (activeHeight - minHeight) / (maxHeight - minHeight)
            
            let bottomPadding = 70 * (1 - progress)
            let horizontalPadding = 16 * (1 - progress)
            
            return VStack(spacing: 0) {
                // Grabber (頂部拖曳條)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 44, height: 6)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isFeedPresented.toggle()
                    }
                
                // Header
                HStack {
                    Text("For your week")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task {
                            await feedVM.fetchPodcasts(for: goals)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // Feed 列表與狀態顯示
                Group {
                    if feedVM.isLoading {
                        Spacer()
                        ProgressView("Finding recommendations...")
                        Spacer()
                    } else if let error = feedVM.errorMessage {
                        Spacer()
                        Text(error).foregroundStyle(.red).padding()
                        Spacer()
                    } else if feedVM.feedItems.isEmpty {
                        Spacer()
                        ContentUnavailableView("No suggestions", systemImage: "sparkles", description: Text("Add goals to see your feed."))
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(feedVM.feedItems) { item in
                                    // 👇 把整塊 VStack 用 Button 包起來
                                    Button {
                                        if let url = item.link {
                                            UIApplication.shared.open(url)
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(item.title)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .lineLimit(2)
                                            Text(item.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        // 👇 把背景與間距放在 label 裡面
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(.background.secondary)
                                        )
                                        .padding(.horizontal)
                                    }
                                    // 👇 關鍵：設定 plain style，這樣文字才不會變成 iOS 預設的按鈕藍色！
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
                            // 👇 優化 1：展開時，為底部保留 40pt 的安全距離，避免被 Home Indicator 擋住
                            .padding(.bottom, 40)
                        }
                    }
                }
                // 收合時隱藏內容，避免 ScrollView 擠壓變形
                .opacity(progress > 0.1 ? 1 : 0)
            }
            .frame(height: activeHeight, alignment: .top)
            .frame(maxWidth: .infinity)
            // 👇 優化 2：最關鍵的一行！將整個 VStack 裁切成圓角，徹底解決內容溢出 (Bleeding) 的問題
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    // 陰影也套用 progress，讓展開時的立體感更自然
                    .shadow(color: .black.opacity(0.15 * progress), radius: 10, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.1))
            )
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isFeedPresented)
            .animation(.interactiveSpring(), value: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        let velocity = value.velocity.height
                        if dragOffset > 50 || velocity > 500 {
                            isFeedPresented = false
                        } else if dragOffset < -50 || velocity < -500 {
                            isFeedPresented = true
                        }
                        dragOffset = 0
                    }
            )
            .ignoresSafeArea(edges: .bottom)
        }
    // MARK: - Goals Tab (目標頁籤)

    private var goalsTab: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 右上角的新增按鈕列
                HStack {
                    Spacer()
                    Button {
                        draftGoalTitles = Array(repeating: "", count: 3) // 重置輸入框
                        showingGoalInput = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // 空狀態顯示
                if goals.isEmpty {
                    ContentUnavailableView(
                        "No goals yet",
                        systemImage: "checklist.unchecked",
                        description: Text("Tap New to add your week goals.")
                    )
                } else {
                    // 目標列表
                    List {
                        // 使用 enumerated 來獲取 index (用於顯示 1. 2. 3. 編號)
                        ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                            HStack(alignment: .top, spacing: 12) {
                                // 序號
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    // 目標標題
                                    Text(goal.title)
                                        .font(.body)
                                        .multilineTextAlignment(.leading)
                                    
                                    // 若有子任務，顯示完成進度 (例如 "1/3 sub-tasks done")
                                    if !goal.subTasks.isEmpty {
                                        let completed = goal.subTasks.filter(\.isCompleted).count
                                        Text("\(completed)/\(goal.subTasks.count) sub-tasks done")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.background.secondary)
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                            // 右滑刪除目標
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    goals.removeAll { $0.id == goal.id }
                                    goals.save() // 刪除後儲存
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .safeAreaInset(edge: .bottom) {
                                            Color.clear.frame(height: 100)
                                        }
                }
            }
            .padding([.horizontal, .bottom])
            .toolbar {
                // 客製化 Navigation Bar 標題，顯示 "Goals" 及 "Week X, YYYY"
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Goals").font(.headline)
                        Text(currentWeekTitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Checklist Tab (檢查表頁籤)

    private var checklistTab: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 空狀態顯示
                if goals.isEmpty {
                    ContentUnavailableView(
                        "No goals yet",
                        systemImage: "checklist",
                        description: Text("Add goals first, then manage sub-tasks here.")
                    )
                } else {
                    List {
                        // 使用 $goals 綁定，讓子視圖可以直接修改狀態 (如 isCompleted)
                        ForEach($goals) { $goal in
                            // 每個主目標作為一個 Section
                            Section {
                                // 該目標下的子任務列表
                                ForEach($goal.subTasks) { $subTask in
                                    HStack(spacing: 12) {
                                        // 完成狀態的打勾按鈕
                                        Image(systemName: subTask.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(subTask.isCompleted ? .green : .secondary)
                                            .font(.title3)
                                            .onTapGesture {
                                                withAnimation {
                                                    subTask.isCompleted.toggle()
                                                    goals.save() // 狀態改變後儲存
                                                }
                                            }
                                        
                                        // 子任務名稱，若完成則加上刪除線
                                        Text(subTask.title)
                                            .strikethrough(subTask.isCompleted, color: .secondary)
                                            .foregroundStyle(subTask.isCompleted ? .secondary : .primary)
                                    }
                                    // 右滑刪除子任務
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            goal.subTasks.removeAll { $0.id == subTask.id }
                                            goals.save()
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }

                                // 內聯新增子任務的元件
                                AddSubTaskRow { title in
                                    goal.subTasks.append(SubTask(title: title))
                                    goals.save()
                                }
                            } header: {
                                // Section 標頭：顯示目標名稱與進度比例
                                HStack {
                                    Text(goal.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .textCase(nil) // 取消全大寫的預設設定
                                    Spacer()
                                    let done = goal.subTasks.filter(\.isCompleted).count
                                    let total = goal.subTasks.count
                                    if total > 0 {
                                        Text("\(done)/\(total)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .safeAreaInset(edge: .bottom) {
                                            Color.clear.frame(height: 100)
                                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Checklist").font(.headline)
                        Text(currentWeekTitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var historyTab: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                if archivedGoals.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("When you archive weekly goals, you'll see them here.")
                    )
                } else {
                    List {
                        ForEach(archivedGoals) { archive in
                            Section(header: Text("Week \(archive.weekOfYear), \(archive.yearForWeek)")) {
                                ForEach(archive.goals) { goal in
                                    VStack(alignment: .leading) {
                                        Text(goal.title).font(.headline)
                                        if !goal.subTasks.isEmpty {
                                            let done = goal.subTasks.filter(\.isCompleted).count
                                            Text("\(done)/\(goal.subTasks.count) sub-tasks")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .safeAreaInset(edge: .bottom) {
                                            Color.clear.frame(height: 100)
                                        }
                }
            }
            .padding([.horizontal, .bottom])
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("History").font(.headline)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }


    // MARK: - Goal Input Sheet (新增目標表單)

    private var goalInputSheet: some View {
        NavigationStack {
            Form {
                // 迴圈產生預設的輸入框
                ForEach(draftGoalTitles.indices, id: \.self) { idx in
                    HStack {
                        Text("Goal \(idx + 1)")
                        // 使用 Binding 安全地存取並修改陣列內的字串
                        TextField("Enter goal", text: Binding(
                            get: { draftGoalTitles[idx] },
                            set: { draftGoalTitles[idx] = $0 }
                        ))
                        .focused($focusedGoalIndex, equals: idx)
                        .onSubmit {
                            if idx + 1 < draftGoalTitles.count {
                                focusedGoalIndex = idx + 1
                            } else {
                                focusedGoalIndex = nil
                            }
                        }
                        .submitLabel(idx + 1 < draftGoalTitles.count ? .next : .done)
                        .textFieldStyle(.roundedBorder)
                    }
                }
                // 允許使用者動態增加輸入框
                Button {
                    draftGoalTitles.append("")
                    focusedGoalIndex = draftGoalTitles.count - 1
                } label: {
                    Label("Add another goal", systemImage: "plus.circle")
                }
            }
            .navigationTitle("New Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingGoalInput = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // 清理空白字串並過濾掉空的目標
                        let trimmed = draftGoalTitles
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        
                        // 轉換成 Goal 模型並加入總目標陣列中
                        let newGoals = trimmed.map { Goal(title: $0) }
                        goals.append(contentsOf: newGoals)
                        goals.save() // 儲存更新
                        showingGoalInput = false // 關閉 Sheet
                    }
                    // 如果所有輸入框都是空的，禁用 Save 按鈕
                    .disabled(draftGoalTitles.allSatisfy {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    })
                }
            }
            .onAppear {
                focusedGoalIndex = draftGoalTitles.isEmpty ? nil : 0
            }
        }
        .presentationDetents([.medium, .large]) // 設定 Sheet 的高度選項
    }

// MARK: - AddSubTaskRow (新增子任務元件)

/// 獨立出來的 UI 元件，專門用來處理在清單內「新增子任務」的輸入列
struct AddSubTaskRow: View {
    var onAdd: (String) -> Void // 按下送出時執行的閉包 (Closure)
    @State private var text = ""
    @FocusState private var isFocused: Bool // 控制鍵盤焦點狀態

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)
                .font(.title3)
            
            TextField("Add sub-task…", text: $text)
                .focused($isFocused)
                .submitLabel(.done) // 將鍵盤的 return 鍵改為 "完成"
                .onSubmit { submit() } // 鍵盤按下完成時觸發
            
            // 當有輸入文字時，顯示送出按鈕
            if !text.isEmpty {
                Button { submit() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain) // 避免整個列表列被視為按鈕
            }
        }
    }

    /// 處理送出邏輯
    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed) // 呼叫父視圖傳入的閉包
        text = "" // 清空輸入框
    }
}
}
