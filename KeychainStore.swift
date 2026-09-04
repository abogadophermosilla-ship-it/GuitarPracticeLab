import Foundation
import Security

struct KeychainStoreError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        if status == errSecMissingEntitlement {
            return "Esta copia de la app no tiene la firma o el permiso de Llavero requeridos. Las claves no fueron borradas; abre una compilación firmada desde Xcode."
        }

        let systemMessage = SecCopyErrorMessageString(status, nil) as String?
        return systemMessage.map { "Error del Llavero (\(status)): \($0)" }
            ?? "Error del Llavero (\(status))"
    }
}

enum KeychainStore {
    private static let service = "com.guitarpracticelab.credentials"
    private static var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "GPLKeychainAccessGroup") as? String
    }

    /// Cuentas que la app guarda en el llavero. Solo se usa para la importación de claves antiguas.
    static let knownAccounts = [
        "gemini-api-key",
        "youtube-data-api-key",
        "hermes-agent-api-key"
    ]

    // Todas las claves viven en el llavero moderno (data protection keychain): ahí el acceso lo
    // gobiernan el entitlement keychain-access-groups y el Team ID, así que el permiso sobrevive a
    // cada recompilación y macOS nunca pide la contraseña del llavero.
    //
    // En el llavero clásico (login.keychain-db) el permiso se ata a la firma exacta del binario que
    // creó el ítem. Como cada build cambia la firma, el sistema pedía la contraseña una vez por
    // clave cada vez que se abría Configuración, y aceptarla no servía de nada: el ítem seguía en el
    // llavero clásico y el siguiente build volvía a preguntar. Añadir kSecAttrAccessGroup no lo
    // arreglaba porque el llavero clásico ignora los access groups.
    private static func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    static func save(_ value: String, account: String) throws {
        let query = baseQuery(account: account)
        let updatedAttributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Actualizar primero evita perder la clave anterior si la firma o los permisos de esta
        // compilación no permiten escribir en el Llavero.
        let updateStatus = SecItemUpdate(query as CFDictionary, updatedAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError(status: updateStatus)
        }

        var newItem = query
        newItem.merge(updatedAttributes) { _, new in new }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError(status: addStatus)
        }
    }

    static func read(account: String) -> String {
        (try? readThrowing(account: account)) ?? ""
    }

    static func readThrowing(account: String) throws -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess else { throw KeychainStoreError(status: status) }
        guard let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Detecta especialmente copias ad-hoc o sin entitlements. Antes `read` convertía este error en
    /// una cadena vacía, haciendo parecer que todas las claves habían desaparecido a la vez.
    static func accessError() -> KeychainStoreError? {
        do {
            _ = try readThrowing(account: "__keychain-access-probe__")
            return nil
        } catch let error as KeychainStoreError {
            return error
        } catch {
            return nil
        }
    }

    /// Copia al llavero moderno las claves que quedaron en el llavero clásico de versiones
    /// anteriores. Solo se llama desde el botón de Configuración: leer el llavero clásico abre el
    /// diálogo de contraseña del sistema, así que nunca debe ocurrir de forma automática.
    /// Devuelve las cuentas que se pudieron importar.
    static func importLegacyItems(accounts: [String] = knownAccounts) -> [String] {
        var imported: [String] = []
        for account in accounts {
            guard read(account: account).isEmpty else { continue }
            guard let legacyValue = readLegacy(account: account), !legacyValue.isEmpty else { continue }
            guard (try? save(legacyValue, account: account)) != nil else { continue }
            // Solo se borra la copia vieja después de confirmar que la nueva se lee bien.
            if read(account: account) == legacyValue {
                deleteLegacy(account: account)
                imported.append(account)
            }
        }
        return imported
    }

    private static func legacyQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: false
        ]
    }

    private static func readLegacy(account: String) -> String? {
        var query = legacyQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteLegacy(account: String) {
        SecItemDelete(legacyQuery(account: account) as CFDictionary)
    }
}
