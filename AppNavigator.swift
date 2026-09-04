import Foundation

/// Estado de navegación compartido: permite que una vista (por ejemplo Tareas) cambie la sección
/// activa del sidebar y le indique al destino qué ítem puntual enfocar (un ejercicio, una canción,
/// un concepto o una clase), sin acoplar las vistas entre sí.
@Observable
final class AppNavigator {
    /// Acción disparada desde el menú de la app (o su atajo de teclado) que tiene que ejecutar una
    /// vista concreta. El menú no puede abrir una hoja por sí mismo: deja el pedido acá y el
    /// Dashboard lo consume y lo limpia.
    enum QuickAction: Equatable {
        case newSession
        case startPractice
    }

    var selection: SidebarSection = .today
    var focusExerciseID: UUID?
    var focusSongID: UUID?
    var focusConceptID: UUID?
    /// Foco para un `LibraryConcept` de Biblioteca — separado de `focusConceptID`, que es el
    /// concepto del banco de preguntas de Academia, otro modelo con otro espacio de `UUID`.
    var focusLibraryConceptID: UUID?
    var focusLessonID: UUID?
    var pendingAction: QuickAction?

    func request(_ action: QuickAction) {
        selection = .today
        pendingAction = action
    }

    func go(to kind: TaskSourceKind, id: UUID?) {
        guard let target = kind.targetSection else { return }
        selection = target
        switch kind {
        case .fretboard: break
        case .library: focusExerciseID = id
        case .libraryConcept: focusLibraryConceptID = id
        case .repertoire: focusSongID = id
        case .academia: focusConceptID = id
        case .clases: focusLessonID = id
        case .profesor, .skillLadder, .manual: break
        }
    }
}
