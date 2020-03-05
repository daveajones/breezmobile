import 'package:breez/bloc/account/account_model.dart';
import 'package:breez/bloc/pos_catalog/actions.dart';
import 'package:breez/bloc/pos_catalog/bloc.dart';
import 'package:breez/bloc/pos_catalog/model.dart';
import 'package:breez/bloc/user_profile/currency.dart';
import 'package:breez/theme_data.dart' as theme;
import 'package:breez/widgets/flushbar.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'item_avatar.dart';

class CatalogItem extends StatelessWidget {
  final AccountModel accountModel;
  final PosCatalogBloc posCatalogBloc;
  final Item _itemInfo;
  final bool _lastItem;
  final Function(String symbol, double price) _addItem;

  CatalogItem(this.accountModel, this.posCatalogBloc, this._itemInfo,
      this._lastItem, this._addItem);

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.bottomCenter, children: <Widget>[
      Slidable(
        actionPane: SlidableDrawerActionPane(),
        actionExtentRatio: 0.25,
        secondaryActions: <Widget>[
          IconSlideAction(
            caption: 'Delete',
            color: Colors.red,
            icon: Icons.delete_forever,
            onTap: () {
              DeleteItem deleteItem = DeleteItem(_itemInfo.id);
              posCatalogBloc.actionsSink.add(deleteItem);
              deleteItem.future.then((_) => showFlushbar(context,
                  message: "${_itemInfo.name} is successfully deleted"));
            },
          ),
        ],
        key: Key(_itemInfo.id.toString()),
        child: ListTile(
          leading: _buildCatalogItemAvatar(),
          title: Text(
            _itemInfo.name,
            style: theme.transactionTitleStyle,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _formattedPrice(),
                      style: theme.transactionAmountStyle,
                    )
                  ]),
            ],
          ),
          onTap: () {
            _addItem(_itemInfo.currency, _satAmount().toDouble());
          },
        ),
      ),
      Divider(
        height: 0.0,
        color: _lastItem
            ? Color.fromRGBO(255, 255, 255, 0.0)
            : Color.fromRGBO(255, 255, 255, 0.12),
        indent: 72.0,
      ),
    ]);
  }

  String _formattedPrice({bool userInput = false, bool includeSymbol = true}) {
    return Currency.fromSymbol(_itemInfo.currency) != null
        ? Currency.fromSymbol(_itemInfo.currency).format(
            Int64(_itemInfo.price.toInt()),
            userInput: userInput,
            includeSymbol: includeSymbol)
        : accountModel.fiatConversionList
            .firstWhere((f) => f.currencyData.shortName == _itemInfo.currency)
            .format(accountModel.fiatConversionList
                .firstWhere(
                    (f) => f.currencyData.shortName == _itemInfo.currency)
                .fiatToSat(_itemInfo.price));
  }

  Int64 _satAmount() {
    return Currency.fromSymbol(_itemInfo.currency) != null
        ? Currency.fromSymbol(_itemInfo.currency)
            .parse(_formattedPrice(userInput: true, includeSymbol: false))
        : accountModel.fiatConversionList
            .firstWhere((f) => f.currencyData.shortName == _itemInfo.currency)
            .fiatToSat(_itemInfo.price);
  }

  Widget _buildCatalogItemAvatar() {
    return ItemAvatar(_itemInfo.imageURL);
  }
}
