import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Client workspace selection")
struct ClientWorkspaceSelectionTests {
    @Test("empty and first-client states resolve without inventing an account")
    func initialSelection() {
        #expect(resolve(nil, []) == nil)
        let first = client(accounts: [])
        let second = client()
        #expect(resolve(nil, [first, second]) == .client(first.id))
        #expect(resolve(.client(first.id), []) == nil)
    }

    @Test("selection follows stable identities through rename, reorder, enablement and insertion")
    func keepsSelectionThroughUpdates() {
        let first = client()
        var second = client()
        let account = second.accounts[0]
        let selection = ClientWorkspaceSelection.account(clientID: second.id, accountID: account.id)
        second.name = "重命名后足够长的客户端名称"
        second.enabled = false
        second.accounts[0].enabled = false
        second.accounts[0].name = "重命名账号"
        second.accounts.reverse()
        #expect(resolve(selection, [second, first, client()]) == selection)
        #expect(resolve(.client(second.id), [first, client(), second]) == .client(second.id))
    }

    @Test("deleting an account returns to its parent without selecting another account")
    func deletedAccountSelectsParent() {
        var target = client()
        let removed = target.accounts.removeFirst()
        let selection = ClientWorkspaceSelection.account(clientID: target.id, accountID: removed.id)
        #expect(resolve(selection, [client(), target]) == .client(target.id))
        target.accounts = []
        #expect(resolve(selection, [target]) == .client(target.id))
    }

    @Test("an account id never changes its owning client implicitly")
    func accountIdentityStaysInParentScope() {
        let owner = client()
        let other = client()
        let wrongParent = ClientWorkspaceSelection.account(clientID: other.id, accountID: owner.accounts[0].id)
        #expect(resolve(wrongParent, [owner, other]) == .client(other.id))
    }

    @Test("deleting a selected client chooses its successor or the nearest preceding client")
    func deletedClientSelectsNeighbor() {
        let first = client()
        let second = client()
        let third = client()
        let previous = [first, second, third]
        #expect(resolve(.client(first.id), [second, third], previous: previous) == .client(second.id))
        #expect(resolve(.client(second.id), [first, third], previous: previous) == .client(third.id))
        #expect(resolve(.account(clientID: third.id, accountID: third.accounts[0].id), [first, second], previous: previous)
                == .client(second.id))
    }

    @Test("creation can explicitly select the new entity while other additions preserve the current selection")
    func explicitCreatedSelection() {
        let first = client()
        let created = client()
        #expect(resolve(.client(first.id), [first, created]) == .client(first.id))
        #expect(resolve(.client(created.id), [first, created]) == .client(created.id))
        let account = created.accounts[0]
        let newAccount = ClientWorkspaceSelection.account(clientID: created.id, accountID: account.id)
        #expect(resolve(newAccount, [first, created]) == newAccount)
    }

    private func resolve(_ selection: ClientWorkspaceSelection?, _ clients: [ClientConfiguration],
                         previous: [ClientConfiguration] = []) -> ClientWorkspaceSelection? {
        ClientWorkspaceSelectionResolver.resolved(selection, clients: clients, previousClients: previous)
    }

    private func client(accounts: [AccountConfiguration]? = nil) -> ClientConfiguration {
        ClientConfiguration(name: "演示客户端", kind: .official, appPath: "",
            address: "127.0.0.1:51234", profileName: "selection-demo-\(UUID().uuidString)",
            bundleIdentifier: "com.example.automaa.selection-fixture",
            accounts: accounts ?? [.init(name: "演示账号 A"), .init(name: "演示账号 B")])
    }
}
