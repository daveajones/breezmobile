import 'dart:async';

import 'package:breez/bloc/account/account_model.dart';
import 'package:breez/bloc/blocs_provider.dart';
import 'package:breez/bloc/invoice/invoice_bloc.dart';
import 'package:breez/bloc/lnurl/lnurl_actions.dart';
import 'package:breez/bloc/lnurl/lnurl_bloc.dart';
import 'package:breez/handlers/lnurl_handler.dart';
import 'package:breez/routes/spontaneous_payment/spontaneous_payment_page.dart';
import 'package:breez/routes/withdraw_funds/reverse_swap_page.dart';
import 'package:breez/services/injector.dart';
import 'package:breez/theme_data.dart' as theme;
import 'package:breez/utils/bip21.dart';
import 'package:breez/utils/btc_address.dart';
import 'package:breez/utils/lnurl.dart';
import 'package:breez/utils/node_id.dart';
import 'package:breez/widgets/error_dialog.dart';
import 'package:breez/widgets/flushbar.dart';
import 'package:breez/widgets/loader.dart';
import 'package:breez/widgets/route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:url_launcher/url_launcher.dart';

class QrActionButton extends StatelessWidget {
  final AccountModel account;
  final GlobalKey firstPaymentItemKey;

  QrActionButton(this.account, this.firstPaymentItemKey);

  @override
  Widget build(BuildContext context) {
    InvoiceBloc invoiceBloc = AppBlocsProvider.of<InvoiceBloc>(context);
    LNUrlBloc lnurlBloc = AppBlocsProvider.of<LNUrlBloc>(context);

    return Padding(
      padding: const EdgeInsets.only(top: 32.0),
      child: Container(
        width: 64,
        height: 64,
        child: FloatingActionButton(
          onPressed: () async {
            String scannedString =
                await Navigator.pushNamed<String>(context, "/qr_scan");
            if (scannedString != null) {
              if (scannedString.isEmpty) {
                showFlushbar(context, message: "QR code wasn't detected.");
                return;
              }
              String lower = scannedString.toLowerCase();

              // lnurl string
              if (isLNURL(lower)) {
                await _handleLNUrl(lnurlBloc, context, scannedString);
                return;
              }

              // lightning address
              final v = parseLightningAddress(scannedString);
              if (v != null) {
                lnurlBloc.lnurlInputSink.add(v);
                return;
              }

              // bip 121
              String lnInvoice = extractBolt11FromBip21(lower);
              if (lnInvoice != null) {
                lower = lnInvoice;
              }

              // regular lightning invoice.
              if (lower.startsWith("lightning:") || lower.startsWith("ln")) {
                invoiceBloc.decodeInvoiceSink.add(scannedString);
                return;
              }

              // bitcoin
              BTCAddressInfo btcInvoice = parseBTCAddress(scannedString);

              if (await _isBTCAddress(btcInvoice.address)) {
                String requestAmount;
                if (btcInvoice.satAmount != null) {
                  requestAmount = account.currency.format(btcInvoice.satAmount,
                      userInput: true,
                      includeDisplayName: false,
                      removeTrailingZeros: true);
                }
                Navigator.of(context).push(FadeInRoute(
                  builder: (_) => ReverseSwapPage(
                      userAddress: btcInvoice.address,
                      requestAmount: requestAmount),
                ));
                return;
              }
              var nodeID = parseNodeId(scannedString);
              if (nodeID != null) {
                Navigator.of(context).push(FadeInRoute(
                  builder: (_) =>
                      SpontaneousPaymentPage(nodeID, firstPaymentItemKey),
                ));
                return;
              }

              if (await canLaunch(scannedString)) {
                _handleWebAddress(context, scannedString);
                return;
              }

              showFlushbar(context, message: "QR code cannot be processed.");
            }
          },
          child: SvgPicture.asset(
            "src/icon/qr_scan.svg",
            color: theme.BreezColors.white[500],
            fit: BoxFit.contain,
            width: 24.0,
            height: 24.0,
          ),
        ),
      ),
    );
  }

  Future<bool> _isBTCAddress(String scannedString) {
    return ServiceInjector()
        .breezBridge
        .validateAddress(scannedString)
        .then((_) => true)
        .catchError((err) => false);
  }

  Future _handleLNUrl(
      LNUrlBloc lnurlBloc, BuildContext context, String lnurl) async {
    Fetch fetchAction = Fetch(lnurl);
    var cancelCompleter = Completer();
    var loaderRoute = createLoaderRoute(context, onClose: () {
      cancelCompleter.complete();
    });
    Navigator.of(context).push(loaderRoute);

    lnurlBloc.actionsSink.add(fetchAction);
    await Future.any([cancelCompleter.future, fetchAction.future]).then(
      (response) {
        Navigator.of(context).removeRoute(loaderRoute);
        if (cancelCompleter.isCompleted) {
          return;
        }

        LNURLHandler(context, lnurlBloc)
            .executeLNURLResponse(context, lnurlBloc, response);
      },
    ).catchError((err) {
      Navigator.of(context).removeRoute(loaderRoute);
      promptError(
          context,
          "Link Error",
          Text("Failed to process link: " + err.toString(),
              style: Theme.of(context).dialogTheme.contentTextStyle));
    });
  }

  void _handleWebAddress(BuildContext context, String url) {
    var dialogTheme = Theme.of(context).dialogTheme;
    var size = MediaQuery.of(context).size;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          scrollable: true,
          title: Container(
            height: 64.0,
            padding: EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 8.0),
            child: Text(
              "Open Link",
              style: dialogTheme.titleTextStyle,
              textAlign: TextAlign.center,
            ),
          ),
          content: Container(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 0.0),
              child: Container(
                width: size.width,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      url,
                      style: dialogTheme.contentTextStyle.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(
                      width: 0.0,
                      height: 16.0,
                    ),
                    Text(
                      "Are you sure you want to open this link?",
                      style: dialogTheme.contentTextStyle,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              style: ButtonStyle(
                overlayColor: MaterialStateProperty.resolveWith<Color>(
                  (Set<MaterialState> states) {
                    if (states.contains(MaterialState.pressed)) {
                      return Colors.transparent;
                    }
                    return null; // Defer to the widget's default.
                  },
                ),
              ),
              child: Text(
                "NO",
                style: Theme.of(context).primaryTextTheme.button,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: ButtonStyle(
                overlayColor: MaterialStateProperty.resolveWith<Color>(
                  (Set<MaterialState> states) {
                    if (states.contains(MaterialState.pressed)) {
                      return Colors.transparent;
                    }
                    return null; // Defer to the widget's default.
                  },
                ),
              ),
              child: Text(
                "YES",
                style: Theme.of(context).primaryTextTheme.button,
              ),
              onPressed: () async {
                await launch(url, forceSafariVC: false);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
