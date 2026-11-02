import AutoMAAKit
import Foundation

enum ClientWorkspaceSelection: Hashable, Sendable {
    case client(UUID)
    case account(clientID: UUID, accountID: UUID)

    var clientID: UUID {
        switch self {
        case let .client(id): id
        case let .account(clientID, _): clientID
        }
    }
}

enum ClientWorkspaceSelectionResolver {
    static func resolved(_ selection: ClientWorkspaceSelection?, clients: [ClientConfiguration],
                         previousClients: [ClientConfiguration] = []) -> ClientWorkspaceSelection? {
        guard !clients.isEmpty else { return nil }
        guard let selection else { return .client(clients[0].id) }
        if let client = clients.first(where: { $0.id == selection.clientID }) {
            if case let .account(_, accountID) = selection,
               !client.accounts.contains(where: { $0.id == accountID }) {
                return .client(client.id)
            }
            return selection
        }
        let previousIndex = previousClients.firstIndex { $0.id == selection.clientID } ?? 0
        return .client(clients[min(previousIndex, clients.count - 1)].id)
    }
}
