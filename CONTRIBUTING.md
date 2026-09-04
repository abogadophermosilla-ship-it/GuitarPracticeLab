# Contribuir a Guitar Practice Lab

Gracias por querer mejorar el proyecto. Las contribuciones pequeñas, enfocadas y acompañadas de una
explicación clara son las más fáciles de revisar.

## Antes de comenzar

- Busca si ya existe un issue relacionado.
- Para cambios grandes de arquitectura o producto, abre primero una propuesta.
- No incluyas claves API, datos personales, grabaciones ni materiales con copyright de terceros.
- El código producido con asistencia de IA es bienvenido, pero debe ser entendido, revisado y probado
  por quien lo aporta.

## Flujo recomendado

1. Crea una rama desde `main`.
2. Implementa un cambio acotado.
3. Agrega o actualiza tests cuando cambie el comportamiento.
4. Ejecuta la suite completa:

   ```bash
   xcodebuild test \
     -project GuitarPracticeLab.xcodeproj \
     -scheme GuitarPracticeLab-Mac \
     -destination 'platform=macOS' \
     CODE_SIGNING_ALLOWED=NO
   ```

5. Describe en el pull request qué cambia, cómo lo probaste y cualquier limitación conocida.

Si modificas `project.yml`, regenera `GuitarPracticeLab.xcodeproj` con XcodeGen e incluye ambos cambios.

## Estilo y alcance

- Mantén la interfaz y los mensajes de usuario en español, salvo que el cambio proponga
  explícitamente localización.
- Favorece cálculos determinísticos para métricas, dominio y progreso. Usa IA para asistir, no para
  inventar mediciones.
- Toda acción generativa que modifique datos o cree archivos debe requerir confirmación del usuario.
- Las integraciones locales deben fallar de forma segura cuando el servicio no esté disponible.

Al contribuir aceptas que tu aporte se distribuya bajo la licencia MIT del repositorio.
