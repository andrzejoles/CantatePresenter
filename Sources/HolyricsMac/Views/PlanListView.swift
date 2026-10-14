import Foundation
import SwiftUI

public struct PlanListView: View {
    @ObservedObject var store = DataStore.shared
    @State private var isCreatingPlan: Bool = false
    @State private var newPlanName: String = ""
    @State private var editingNoteItemId: UUID?
    @State private var tempNoteText: String = ""
    
    public init() {}
    
    private var activePlanItems: [PlanItem] {
        return store.activePlan?.items ?? []
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // Plan Header & Selector
            VStack(spacing: 8) {
                HStack {
                    Picker("Plan:", selection: Binding(
                        get: { store.activePlanId ?? store.plans.first?.id ?? UUID() },
                        set: { store.activePlanId = $0 }
                    )) {
                        ForEach(store.plans) { plan in
                            Text(plan.name).tag(plan.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .font(.scaled(12, scale: scale))
                    
                    Button(action: {
                        newPlanName = "Plan \(Date().formatted(date: .abbreviated, time: .omitted))"
                        isCreatingPlan = true
                    }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Utwórz nowy plan")
                    
                    if store.plans.count > 1, let activeId = store.activePlanId {
                        Button(action: {
                            store.deletePlan(id: activeId)
                        }) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Usuń ten plan")
                    }
                }
                
                HStack {
                    Text("\(activePlanItems.count) pieśni w planie")
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !activePlanItems.isEmpty {
                        Button(action: {
                            if let firstId = activePlanItems.first?.songId,
                               let song = store.songs.first(where: { $0.id == firstId }) {
                                store.present(song: song, slideIndex: 0)
                                store.selectedSongId = song.id
                            }
                        }) {
                            Label("Uruchom plan", systemImage: "play.fill")
                                .font(.scaled(11, weight: .semibold, scale: scale))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Plan items list
            if activePlanItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Plan nabożeństwa jest pusty")
                        .font(.scaled(13, weight: .medium, scale: scale))
                        .foregroundColor(.secondary)
                    Text("Kliknij prawym przyciskiem myszy na pieśń w bibliotece lub kliknij przycisk '+ Do planu', aby dodać pieśni.")
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer()
                }
            } else {
                List {
                    ForEach(Array(activePlanItems.enumerated()), id: \.element.id) { index, item in
                        let song = store.songs.first(where: { $0.id == item.songId })
                        PlanItemRowView(
                            index: index + 1,
                            item: item,
                            song: song,
                            isLive: store.activeSong?.id == item.songId && store.isLive,
                            isSelected: store.selectedSongId == item.songId,
                            scale: scale,
                            onMoveUp: {
                                moveItem(from: index, to: max(0, index - 1))
                            },
                            onMoveDown: {
                                moveItem(from: index, to: min(activePlanItems.count - 1, index + 1))
                            },
                            onRemove: {
                                if let planId = store.activePlanId {
                                    store.removePlanItem(id: item.id, in: planId)
                                }
                            },
                            onSelect: {
                                if let song = song {
                                    store.selectedSongId = song.id
                                }
                            },
                            onPresent: {
                                if let song = song {
                                    store.present(song: song, slideIndex: 0)
                                    store.selectedSongId = song.id
                                }
                            }
                        )
                    }
                }
                .listStyle(InsetListStyle())
            }
        }
        .sheet(isPresented: $isCreatingPlan) {
            VStack(spacing: 16) {
                Text("Utwórz nowy plan nabożeństwa")
                    .font(.scaled(14, weight: .bold, scale: scale))
                
                TextField("Nazwa planu (np. Niedziela 10:00)", text: $newPlanName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 300)
                
                HStack {
                    Button("Anuluj") {
                        isCreatingPlan = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Utwórz") {
                        if !newPlanName.isEmpty {
                            _ = store.createPlan(name: newPlanName)
                        }
                        isCreatingPlan = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }
    
    private func moveItem(from: Int, to: Int) {
        guard let planId = store.activePlanId, from != to else { return }
        var source = IndexSet()
        source.insert(from)
        let destination = to > from ? to + 1 : to
        store.movePlanItem(from: source, to: destination, in: planId)
    }
}

private struct PlanItemRowView: View {
    let index: Int
    let item: PlanItem
    let song: Song?
    let isLive: Bool
    let isSelected: Bool
    let scale: Double
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void
    let onSelect: () -> Void
    let onPresent: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Index circle
            ZStack {
                Circle()
                    .fill(isLive ? Color.red : Color.secondary.opacity(0.2))
                    .frame(width: 22, height: 22)
                Text("\(index)")
                    .font(.scaled(10, weight: .bold, scale: scale))
                    .foregroundColor(isLive ? .white : .primary)
            }
            
            // Song Details
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(song?.title ?? "Nieznana pieśń")
                        .font(.scaled(12, weight: .semibold, scale: scale))
                        .lineLimit(1)
                    
                    if let key = song?.key, !key.isEmpty {
                        Text(key)
                            .font(.scaled(9, weight: .bold, scale: scale))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(3)
                    }
                }
                
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.scaled(10, scale: scale))
                        .foregroundColor(.orange)
                        .italic()
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Quick action buttons
            HStack(spacing: 2) {
                Button(action: onPresent) {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Prezentuj teraz")
                
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(2)
                .help("Przesuń wyżej")
                
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(2)
                .help("Przesuń niżej")
                
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(2)
                .help("Usuń z planu")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
