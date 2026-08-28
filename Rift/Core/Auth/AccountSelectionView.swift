// SPDX-License-Identifier: GPL-3.0-only
//
// AccountSelectionView — the login-time account chooser. Presented after the
// Google login captures cookies, when multiple accounts (primary + brand) are
// available. Lets the user pick which identity to authenticate as.

import SwiftUI

struct AccountSelectionView: View {
    @ObservedObject var auth: AuthController

    var body: some View {
        VStack(spacing: 24) {
            header

            if auth.isFetchingAccounts {
                loadingView
            } else if let error = auth.accountsError, auth.accounts.isEmpty {
                errorView(error)
            } else {
                accountsList
            }

            Spacer(minLength: 0)

            if !auth.accounts.isEmpty {
                footerActions
            }
        }
        .padding(24)
        .frame(width: 440, height: 480)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("Choose an Account")
                .font(.title2.bold())
            Text("Select which YouTube Music identity to use. You can switch by signing out and back in.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading accounts…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel") { auth.cancelChooser() }
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            VStack(spacing: 4) {
                Text("Couldn't load accounts")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Continue with Primary") { auth.continueWithPrimary() }
                    .buttonStyle(.borderedProminent)
                Button("Cancel") { auth.cancelChooser() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Accounts list

    private var accountsList: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Inline error banner (e.g., session switch failure).
                if let error = auth.accountsError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
                    .padding(.bottom, 4)
                }
                ForEach(auth.accounts) { account in
                    AccountRow(
                        account: account,
                        onSelect: { Task { await auth.selectAccount(account) } }
                    )
                }
            }
        }
    }

    // MARK: - Footer

    private var footerActions: some View {
        HStack {
            Button("Cancel") { auth.cancelChooser() }
                .buttonStyle(.bordered)
            Spacer()
            if auth.accountsError != nil {
                Button("Continue with Primary") { auth.continueWithPrimary() }
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - AccountRow

/// A single account row in the chooser — avatar, name, handle, type label.
private struct AccountRow: View {
    let account: UserAccount
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if let handle = account.handle {
                        Text(handle)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(account.typeLabel)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(rowBackground)
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var avatar: some View {
        Group {
            if let url = account.thumbnailURL {
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { avatarPlaceholder }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(.circle)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
            }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isHovering {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        } else {
            Color.clear
        }
    }
}
