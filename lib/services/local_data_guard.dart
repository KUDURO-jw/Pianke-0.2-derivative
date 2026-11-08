/// Keeps automatic cloud replacement away from an open editor or restore preview.
/// Owners must release their hold when saved, cancelled, or disposed.
class LocalDataGuard {
  LocalDataGuard._();

  static final Set<Object> _owners = {};
  static bool get isEditing => _owners.isNotEmpty;
  static void hold(Object owner) => _owners.add(owner);
  static void release(Object owner) => _owners.remove(owner);
}
