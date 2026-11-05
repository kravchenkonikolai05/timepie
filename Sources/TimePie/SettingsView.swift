import SwiftUI

/// Preferences, kept in UserDefaults. Each one is a key here and a row on the page.
enum Settings {
    /// The week's average per day, small and grey under the total in the donut.
    static let showDayAverage = "showDayAverage"
}

/// The settings page, in place of the week like stats, friends and the leaderboard.
/// One inset grouped card of rows, as in System Settings; new settings are new rows.
struct SettingsView: View {
    @AppStorage(Settings.showDayAverage) private var showDayAverage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chart")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
            VStack(spacing: 0) {
                Toggle(isOn: $showDayAverage) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show average per day")
                        Text("Under the week's total: what it comes to per day so far, like ~3,5h.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quinary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
