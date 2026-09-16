part of 'inventory_screen.dart';

class _Header extends StatelessWidget {
  const _Header({
    required this.onMenu,
    required this.onAdd,
    required this.onDelete,
  });
  final VoidCallback onMenu;
  final VoidCallback onAdd;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 6),
      child: Row(
        children: [
          // RTL: first child = right side → title on the right
          const Text(
            'إدارة الكروت',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: KayanColors.textPrimary,
            ),
          ),
          const Spacer(),
          // From right to left after title: archive, add, menu (menu ends at far left)
          _RoundIcon(icon: Icons.delete_outline, onTap: onDelete),
          const SizedBox(width: 8),
          _RoundIcon(icon: Icons.add, onTap: onAdd),
          const SizedBox(width: 8),
          _RoundIcon(icon: Icons.more_horiz, onTap: onMenu),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE8EEF2),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: KayanColors.textPrimary),
        ),
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KayanColors.primary,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
