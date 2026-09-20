              if (customer.status == CustomerStatus.provisional) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.netColors.warningContainer,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.netColors.warning.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.account_balance_wallet_outlined, color: context.netColors.warning, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'حساب دفتر مؤقت',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: context.netColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'تم إنشاء هذا الحساب تلقائياً عند استلام إيداع من رقم غير مسجّل. يمكنك اعتماده كعميل أو ربط رقم جوال.',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12.5,
                          height: 1.35,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _promoteToCustomer,
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                        label: const Text('اعتماد كعميل', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
