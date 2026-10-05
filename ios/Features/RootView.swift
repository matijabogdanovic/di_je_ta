import SwiftUI
import Charts
import WeightCoachCore
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: AppModel
    var body: some View {
        TabView {
            TodayView(model: model).tabItem { Label("Today",systemImage:"sun.max") }
            MealsView(model: model).tabItem { Label("Meals",systemImage:"fork.knife") }
            HistoryView(model: model).tabItem { Label("History",systemImage:"chart.xyaxis.line") }
            NavigationStack { ContentUnavailableView("Your journal comes first", systemImage:"sparkles", description:Text("AI coaching arrives in Milestone 4. For now, follow your weekly trend and keep logging." )).navigationTitle("Coach") }.tabItem { Label("Coach",systemImage:"sparkles") }
            SettingsView(model:model).tabItem { Label("Settings",systemImage:"gearshape") }
        }.tint(.teal)
        .alert("Couldn’t complete that action", isPresented:Binding(get:{model.error != nil},set:{if !$0 { model.error = nil }})) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
}
struct TodayView: View {
    @Bindable var model: AppModel
    @State private var addingMeal = false
    @State private var addingWeight = false
    private var nutrition: Nutrition { Trends.dailyNutrition(meals:model.meals,day:Date()) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Text(Date(),format:.dateTime.weekday(.wide).month().day()).font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment:.leading,spacing:12) {
                        Text("A little progress, every day.").font(.title2.bold())
                        HStack(alignment:.firstTextBaseline) { Text(nutrition.calories,format:.number.precision(.fractionLength(0))).font(.system(size:48,weight:.semibold,design:.rounded)); Text("/ \(Int(model.targets.calories)) kcal").foregroundStyle(.secondary) }
                        ProgressView(value:min(nutrition.calories,model.targets.calories),total:model.targets.calories).tint(.teal)
                        Text("\(Int(max(0,model.targets.calories-nutrition.calories))) kcal remaining").font(.caption).foregroundStyle(.secondary)
                        HStack { metric("Protein",nutrition.protein, suffix:"/ \(Int(model.targets.protein)) g"); Spacer(); metric("Carbs",nutrition.carbs,suffix:"g"); Spacer(); metric("Fat",nutrition.fat,suffix:"g") }
                    }.padding().background(.teal.opacity(0.08),in:RoundedRectangle(cornerRadius:22))
                    Button { addingMeal = true } label: { Label("Add Meal",systemImage:"plus").font(.headline).frame(maxWidth:.infinity).padding(8) }.buttonStyle(.borderedProminent)
                    HStack {
                        VStack(alignment:.leading,spacing:6) {
                            Text("Weight trend").font(.headline)
                            if let average = Trends.average(weights:model.weights,ending:Date()) {
                                Text("\(model.displayWeight(average),specifier:"%.1f") \(model.weightUnit)").font(.title.bold())
                                Text("7-day average · \(model.weights.filter { $0.date >= Calendar.current.date(byAdding:.day,value:-6,to:Calendar.current.startOfDay(for:Date()))! && $0.date < Calendar.current.startOfDay(for:Date()).addingTimeInterval(86400) }.count) weigh-ins").font(.caption).foregroundStyle(.secondary)
                            } else { Text("Log a weigh-in to begin").foregroundStyle(.secondary) }
                            if let latest = model.weights.last { Text("Latest: \(model.displayWeight(latest.weightKg),specifier:"%.1f") \(model.weightUnit) · \(latest.date.formatted(date:.abbreviated,time:.omitted))").font(.caption) }
                        }; Spacer(); Button("Log weight") { addingWeight = true }.buttonStyle(.bordered)
                    }.padding().background(.quaternary,in:RoundedRectangle(cornerRadius:18))
                    VStack(alignment:.leading,spacing:10) {
                        Label("Keep the bigger picture in view",systemImage:"leaf").font(.headline)
                        Text("Daily weight can fluctuate. Your 7-day average helps you see the direction over time.").foregroundStyle(.secondary)
                    }
                    HStack { Label("Activity",systemImage:"figure.walk"); Spacer(); Text("Not connected").foregroundStyle(.secondary) }
                    HStack { Label("Sleep",systemImage:"moon"); Spacer(); Text("Not connected").foregroundStyle(.secondary) }
                    HStack { Label("Fasting",systemImage:"timer"); Spacer(); Text("Coming later").foregroundStyle(.secondary) }
                    Text("Today’s meals").font(.headline)
                    let todayMeals = model.meals.filter { Calendar.current.isDateInToday($0.timestamp) }
                    if todayMeals.isEmpty { Text("Your first meal starts here.").foregroundStyle(.secondary) }
                    ForEach(todayMeals) { meal in MealRow(meal:meal) }
                }.padding()
            }.navigationTitle("Today")
            .sheet(isPresented:$addingMeal) { MealEditor(model:model,meal:Meal(items:[MealItem()])) }
            .sheet(isPresented:$addingWeight) { WeightEditor(model:model) }
        }
    }
    private func metric(_ name: String,_ value:Double,suffix:String) -> some View {
        VStack(alignment:.leading) { Text(name).font(.caption).foregroundStyle(.secondary); Text("\(Int(value)) \(suffix)").font(.subheadline.bold()) }
    }
}
struct MealRow: View {
    let meal: Meal
    var body: some View { HStack { VStack(alignment:.leading) { Text(meal.mealType).font(.headline); Text(meal.items.map(\.foodName).joined(separator:", ")).font(.caption).foregroundStyle(.secondary); Text(meal.timestamp,format:.dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary) }; Spacer(); Text("\(Int(meal.totals.calories)) kcal").font(.subheadline.monospacedDigit()) } }
}
struct MealsView: View {
    @Bindable var model: AppModel
    @State private var adding = false
    private var days:[Date] { Array(Set(model.meals.map { Calendar.current.startOfDay(for:$0.timestamp) })).sorted(by:>) }
    var body: some View {
        NavigationStack {
            List {
                if model.meals.isEmpty { ContentUnavailableView("No meals yet",systemImage:"fork.knife",description:Text("Add a meal to start your journal.")) }
                ForEach(days,id:\.self) { day in
                    Section(day.formatted(date:.abbreviated,time:.omitted)) {
                        ForEach(model.meals.filter { Calendar.current.isDate($0.timestamp,inSameDayAs:day) }) { meal in
                            NavigationLink { MealEditor(model:model,meal:meal) } label: { MealRow(meal:meal) }
                            .swipeActions { Button("Delete",role:.destructive) { model.perform { try model.store.deleteMeal(meal.id) } } }
                        }
                    }
                }
            }.navigationTitle("Meals").toolbar { Button { adding = true } label: { Image(systemName:"plus") } }
            .sheet(isPresented:$adding) { MealEditor(model:model,meal:Meal(items:[MealItem()])) }
        }
    }
}
struct MealEditor: View {
    @Bindable var model: AppModel
    @State var meal: Meal
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    DatePicker("When",selection:$meal.timestamp,in:...Date())
                    Picker("Type",selection:$meal.mealType) { ForEach(["Breakfast","Lunch","Dinner","Snack"],id:\.self) { Text($0) } }
                    TextField("Notes",text:$meal.notes,axis:.vertical)
                }
                ForEach($meal.items) { $item in
                    Section {
                        TextField("Food name",text:$item.foodName)
                        numeric("Amount (g)",$item.finalGrams)
                        numeric("Calories (kcal)",$item.final.calories)
                        numeric("Protein (g)",$item.final.protein)
                        numeric("Carbs (g)",$item.final.carbs)
                        numeric("Fat (g)",$item.final.fat)
                        if let estimate = item.estimate { Text("Original estimate: \(Int(estimate.calories)) kcal · confidence \(Int((item.confidence ?? 0)*100))%").font(.caption).foregroundStyle(.secondary) }
                        Button("Remove food",role:.destructive) { meal.items.removeAll { $0.id == item.id } }
                    }
                }
                Button { meal.items.append(MealItem()) } label: { Label("Add another food",systemImage:"plus") }
                Section("Meal total") { Text("\(Int(meal.totals.calories)) kcal · \(Int(meal.totals.protein)) g protein") }
                Section { Button("Save meal") { if model.perform({ try model.store.save(meal) }) { dismiss() } }.disabled(meal.items.isEmpty || !meal.items.allSatisfy(\.isValid)) }
            }.navigationTitle("Meal details").toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
private func numeric(_ title:String,_ value:Binding<Double>) -> some View {
    HStack { Text(title); Spacer(); TextField(title,value:value,format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:110) }
}
struct WeightEditor: View {
    @Bindable var model: AppModel
    @State private var date = Date()
    @State private var amount = ""
    @Environment(\.dismiss) private var dismiss
    private var parsed:Double? { Double(amount.replacingOccurrences(of:",",with:".")) }
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date",selection:$date,in:...Date(),displayedComponents:.date)
                TextField("Weight (\(model.weightUnit))",text:$amount).keyboardType(.decimalPad)
                Text("One weigh-in per day. Saving again updates that day’s value.").font(.caption).foregroundStyle(.secondary)
                Button("Save weigh-in") {
                    guard let value = parsed else { return }
                    let kg = model.targets.units == "imperial" ? value / 2.2046226218 : value
                    if model.perform({ try model.store.save(WeighIn(date:date,weightKg:kg)) }) { dismiss() }
                }.disabled(parsed.map { !$0.isFinite || $0 <= 0 } ?? true)
            }.navigationTitle("Log weight").toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var range = 30
    @State private var addingWeight = false
    private var start:Date { range == 0 ? .distantPast : Calendar.current.date(byAdding:.day,value:1-range,to:Calendar.current.startOfDay(for:Date()))! }
    private var weights:[WeighIn] { model.weights.filter { $0.date >= start } }
    private var days:[Date] { Array(Set(model.meals.filter { $0.timestamp >= start }.map { Calendar.current.startOfDay(for:$0.timestamp) })).sorted() }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    Picker("Range",selection:$range) { ForEach([7,30,90,365,0],id:\.self) { Text($0 == 0 ? "All" : $0 == 365 ? "1 yr" : "\($0)d").tag($0) } }.pickerStyle(.segmented)
                    Text("Weight · \(model.weightUnit)").font(.headline)
                    if weights.isEmpty { Text("No weigh-ins in this range.").foregroundStyle(.secondary) }
                    else {
                        Chart {
                            ForEach(weights) { w in
                                PointMark(x:.value("Date",w.date),y:.value("Weight",model.displayWeight(w.weightKg))).foregroundStyle(.gray)
                                if let average = Trends.average(weights:model.weights,ending:w.date) { LineMark(x:.value("Date",w.date),y:.value("7-day average",model.displayWeight(average))).foregroundStyle(.teal) }
                            }
                        }.chartYScale(domain:.automatic(includesZero:false)).frame(height:220)
                        Text("Dots: daily weight · Line: 7-day average").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Calories").font(.headline)
                    Chart(days,id:\.self) { day in
                        BarMark(x:.value("Date",day,unit:.day),y:.value("Calories",Trends.dailyNutrition(meals:model.meals,day:day).calories)).foregroundStyle(.teal)
                        RuleMark(y:.value("Target",model.targets.calories)).foregroundStyle(.orange).lineStyle(StrokeStyle(dash:[4]))
                    }.frame(height:180)
                    Text("Protein · g").font(.headline)
                    Chart(days,id:\.self) { day in BarMark(x:.value("Date",day,unit:.day),y:.value("Protein",Trends.dailyNutrition(meals:model.meals,day:day).protein)).foregroundStyle(.indigo) }.frame(height:180)
                    if let average = Trends.weeklyNutrition(meals:model.meals,ending:Date()) { Text("Last 7 days: \(Int(average.calories)) kcal and \(Int(average.protein)) g protein per logged day.").font(.subheadline) }
                    Text("Missing days are excluded from averages. Partially logged days are included; finish logging before interpreting nutrition trends.").font(.caption).foregroundStyle(.secondary)
                    Text("Weigh-ins").font(.headline)
                    ForEach(weights.reversed()) { w in HStack { Text(w.date,style:.date); Spacer(); Text("\(model.displayWeight(w.weightKg),specifier:"%.1f") \(model.weightUnit)"); Button(role:.destructive) { model.perform { try model.store.deleteWeight(w.id) } } label: { Image(systemName:"trash") } } }
                }.padding()
            }.navigationTitle("History").toolbar { Button("Log weight") { addingWeight = true } }.sheet(isPresented:$addingWeight) { WeightEditor(model:model) }
        }
    }
}
struct BackupDocument: FileDocument {
    static var readableContentTypes:[UTType] { [.json] }
    var data:Data
    init(data:Data) { self.data = data }
    init(configuration:ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var draft = Targets()
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmRestore = false
    @State private var backup = BackupDocument(data:Data())
    var body: some View {
        NavigationStack {
            Form {
                Section("Daily targets") { numeric("Calories (kcal)",$draft.calories); numeric("Protein (g)",$draft.protein) }
                Section("Weight goals") { numeric("Target weight (kg)",$draft.weight); numeric("Loss rate (kg/week)",$draft.lossRate); Picker("Units",selection:$draft.units) { Text("Metric").tag("metric"); Text("Imperial").tag("imperial") }; Text("Stored weights and goal inputs use kilograms. Displayed weigh-ins follow your unit preference.").font(.caption).foregroundStyle(.secondary) }
                Button("Save targets") { model.perform { try model.store.save(draft) } }
                Section("Connections") { Label("ChatGPT · Milestone 2",systemImage:"sparkles"); Label("Desktop Sync · Milestone 3",systemImage:"desktopcomputer"); Label("Garmin · Milestone 5",systemImage:"figure.run") }
                Section("Your data") {
                    Button("Export JSON backup") { if model.perform({ backup = BackupDocument(data:try model.store.exportData()) }) { exporting = true } }
                    Button("Restore JSON backup",role:.destructive) { confirmRestore = true }
                    Text("Your journal stays on this iPhone. Export contains health data; choose a private backup destination.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings").onAppear { draft = model.targets }
            .confirmationDialog("Restore replaces all current journal data",isPresented:$confirmRestore,titleVisibility:.visible) { Button("Choose backup",role:.destructive) { importing = true } }
            .fileExporter(isPresented:$exporting,document:backup,contentType:.json,defaultFilename:"weight-coach-backup") { result in if case .failure(let error) = result { model.error = error.localizedDescription } }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
                model.perform {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try model.store.importData(Data(contentsOf:url)); draft = try model.store.targets()
                }
            }
        }
    }
}
