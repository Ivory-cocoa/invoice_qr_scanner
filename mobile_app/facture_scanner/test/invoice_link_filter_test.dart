import 'package:facture_scanner/screens/invoice_picker_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Filtre « liées à un OT / non liées » de la liste des factures du
/// Gestionnaire OT. L'écran l'applique aussi lui-même, pour rester juste
/// face à un serveur qui ne connaît pas encore le paramètre `link_state`.
void main() {
  test('valeurs envoyées au serveur', () {
    expect(InvoiceLinkFilter.all.apiValue, 'all');
    expect(InvoiceLinkFilter.linked.apiValue, 'linked');
    expect(InvoiceLinkFilter.unlinked.apiValue, 'unlinked');
  });

  test('« Liées à un OT » ne garde que les factures avec au moins un OT', () {
    expect(InvoiceLinkFilter.linked.keeps(0), isFalse);
    expect(InvoiceLinkFilter.linked.keeps(1), isTrue);
    expect(InvoiceLinkFilter.linked.keeps(3), isTrue);
  });

  test('« Non liées » ne garde que les factures sans OT', () {
    expect(InvoiceLinkFilter.unlinked.keeps(0), isTrue);
    expect(InvoiceLinkFilter.unlinked.keeps(2), isFalse);
  });

  test('« Toutes » garde tout', () {
    expect(InvoiceLinkFilter.all.keeps(0), isTrue);
    expect(InvoiceLinkFilter.all.keeps(5), isTrue);
  });
}
