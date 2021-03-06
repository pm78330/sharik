import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info/package_info.dart';
import 'package:pedantic/pedantic.dart';
import 'package:provider/provider.dart';
import 'package:sharik_wrapper/sharik_wrapper.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:simple_connectivity/simple_connectivity.dart' as s;

import '../cast.dart';
import '../conf.dart';
import '../locale.dart';
import '../models/app.dart';
import '../models/file.dart';

class SharePage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return ShareState();
  }
}

class ShareState extends State<SharePage> with TickerProviderStateMixin {
  AnimationController _ipController;
  Animation _ipAnimation;
  AnimationController _conController;
  Animation _conAnimation;

  AppModel _model;
  FileModel _file;

  String ip;
  String network;
  bool wifi = false;
  bool tether = false;
  int port = 0;
  HttpServer _server;

  Future<bool> _isPortFree(int port) async {
    try {
      final _ = await HttpServer.bind(InternetAddress.anyIPv4, port);
      await _.close(force: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<dynamic> _getPort() async {
    for (final port in ports) {
      if (await _isPortFree(port)) {
        return port;
      }
    }

    final _ = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    await _.close(force: true);
    return _.port;
  }

  // ignore: avoid_void_async
  void serve() async {
    await for (final request in _server) {
      if (request.requestedUri.toString().split('/').length == 4 &&
          request.requestedUri.toString().split('/').last == 'sharik.json') {
        final info = await PackageInfo.fromPlatform();
        final v = '${info.version.split('.')[0]}.${info.version.split('.')[1]}';

        request.response.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        request.response.write(jsonEncode({
          'sharik': v,
          'type': _file.type.toString().split('.').last,
          'name': _file.name,
          'os': Platform.operatingSystem,
        }));
        await request.response.close();
      } else {
        if (_file.type == FileTypeModel.file ||
            _file.type == FileTypeModel.app) {
          final f = File(_file.data);
          final size = await f.length();

          request.response.headers.contentType =
              ContentType('application', 'octet-stream', charset: 'utf-8');

          request.response.headers.add(
            'Content-Transfer-Encoding',
            'Binary',
          );

          request.response.headers.add(
            'Content-disposition',
            'attachment; filename=${Uri.encodeComponent(_file.type == FileTypeModel.file ? _file.name : '${_file.name}.apk')}',
          );
          request.response.headers.add(
            'Content-length',
            size,
          );

          await f
              .openRead()
              .pipe(request.response)
              .catchError((e) {})
              .then((a) {
            request.response.close();
          });
        } else {
          request.response.headers.contentType =
              ContentType('text', 'plain', charset: 'utf-8');
          request.response.write(_file.data);
          await request.response.close();
        }
      }
    }
  }

  Future getIp() async {
    return SharikWrapper.getLocalIp;
  }

  Future<bool> iosHotspot() async {
    final list = await NetworkInterface.list(
        includeLinkLocal: false,
        includeLoopback: false,
        type: InternetAddressType.IPv4);

    for (final el in list) {
      if (el.name.startsWith('bridge')) {
        return true;
      }
    }

    return false;
  }
  // Future<String> getIp() async {
  //   final list = await NetworkInterface.list(
  //       includeLinkLocal: false,
  //       includeLoopback: false,
  //       type: InternetAddressType.IPv4);
  //
  //   for (final el in list) {
  //     final addr = el.addresses[0].toString();
  //
  //     if (addr.startsWith('10.') || addr.endsWith('.1')) {
  //       continue;
  //     }
  //
  //     final arr = addr.split('.');
  //
  //     final mask = '${addr[0]}.${addr[1]}.${addr[2]}.';
  //
  //     for (var i = 1; i < 255; i++) {
  //       ping(mask + i.toString()).then((value) {
  //         if (value) {
  //           print('FOUND!!!: $mask$i');
  //         }
  //       });
  //     }
  //
  //     print(addr);
  //   }
  //
  //   return '123';
  // }
  //
  // Future<bool> ping(String addr) async {
  //   const arr = [
  //     'unreachable',
  //     'unknown',
  //     '100% packet loss',
  //     'failed',
  //     'failure',
  //     '100% loss',
  //     'timed out',
  //   ];
  //
  //   final r = await Process.run(
  //       '/system/bin/ping', ['-c', '1', '-w', '1', '168.0.0.1']);
  //   final out =
  //       ((r.stdout as String).isNotEmpty ? r.stdout : r.stderr).toString();
  //
  //   for (final el in arr) {
  //     if (out.contains(el)) {
  //       return false;
  //     }
  //   }
  //   return true;
  // }

  // ignore: avoid_void_async, avoid_positional_boolean_parameters
  void updIp([bool hard = false]) async {
    setState(() => ip = L('loading...', _model.localeAdapter));

    if (!_ipController.isAnimating) {
      unawaited(_ipController.forward().then((value) => _ipController.reset()));
    }

    final _ip = cast<String>(await getIp());

    if (port == 0 && _ip != null) {
      port = cast<int>(await _getPort());
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      serve();
    }
    setState(() => ip = 'http://$_ip:$port');
  }

  // ignore: avoid_void_async
  void updCon() async {
    setState(() {
      network = L('loading...', _model.localeAdapter);
      wifi = false;
      tether = false;
    });
    if (!_ipController.isAnimating) {
      unawaited(
          _conController.forward().then((value) => _conController.reset()));
    }

    var w = false;
    var t = false;

    if (Platform.isAndroid) {
      w = await WiFiForIoTPlugin.isConnected();
      t = await WiFiForIoTPlugin.isWiFiAPEnabled();
    } else if (Platform.isIOS || Platform.isMacOS) {
      final connectivityResult = await s.Connectivity().checkConnectivity();

      if (connectivityResult == s.ConnectivityResult.wifi) {
        w = true;
      } else if (await iosHotspot()) {
        t = true;
      }
    }

    setState(() {
      wifi = w;
      tether = t;
      if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
        network = L('Undefined', _model.localeAdapter);
      } else if (w) {
        network = 'Wi-Fi';
      } else if (t) {
        network = L('Mobile Hotspot', _model.localeAdapter);
      } else {
        network = L('Not connected', _model.localeAdapter);
      }
    });
    updIp();
  }

  @override
  void dispose() {
    if (_server != null) _server.close();

    if (_conController.isAnimating) _conController.stop();

    if (_ipController.isAnimating) _ipController.stop();

    super.dispose();
  }

  @override
  void initState() {
    _model = Provider.of<AppModel>(context, listen: false);
    _file = _model.file;

    ip = L('loading...', _model.localeAdapter);
    network = L('loading...', _model.localeAdapter);

    _ipController = AnimationController(
        duration: const Duration(milliseconds: 200), vsync: this);
    _ipAnimation = Tween(begin: 0, end: pi).animate(_ipController);

    _conController = AnimationController(
        duration: const Duration(milliseconds: 200), vsync: this);
    _conAnimation = Tween(begin: 0, end: pi).animate(_conController);

    updCon();

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 24, right: 24, top: 8),
      child: Column(
        children: <Widget>[
          Container(
            height: 46,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.deepPurple[400],
            ),
            child: Row(
              children: <Widget>[
                SvgPicture.asset(
                  _file.icon,
                  //todo: add semantics stuff everywhere
                  semanticsLabel: 'file',
                  width: 18,
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      _file.name,
                      style: GoogleFonts.getFont(
                        L('Andika', _model.localeAdapter),
                        color: Colors.white,
                        fontSize: 18,
                      ),
                      maxLines: 1,
                    ),
                  ),
                )
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.deepPurple[400],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.only(left: 16),
                  margin: const EdgeInsets.only(top: 18),
                  child: SvgPicture.asset(
                    'assets/icon_network.svg',
                    semanticsLabel: 'network ',
                    width: 18,
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              network,
                              style: GoogleFonts.getFont(
                                L('Andika', _model.localeAdapter),
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          RichText(
                            text: TextSpan(
                                style: GoogleFonts.getFont(
                                  L('Andika', _model.localeAdapter),
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                                children: [
                                  TextSpan(
                                      text: L(
                                          'Connect to', _model.localeAdapter)),
                                  if (Platform.isAndroid || Platform.isIOS)
                                    TextSpan(
                                        text: ' Wi-Fi ',
                                        style: TextStyle(
                                            color: wifi
                                                ? Colors.green[100]
                                                : Colors.red[100]))
                                  else
                                    const TextSpan(text: ' Wi-Fi '),
                                  TextSpan(
                                      text: L(
                                          'or set up a', _model.localeAdapter)),
                                  if (Platform.isAndroid || Platform.isIOS)
                                    TextSpan(
                                        text: L(' Mobile Hotspot',
                                            _model.localeAdapter),
                                        style: TextStyle(
                                            color: tether
                                                ? Colors.green[100]
                                                : Colors.red[100]))
                                  else
                                    TextSpan(
                                        text: L(' Mobile Hotspot',
                                            _model.localeAdapter)),
                                ]),
                          ),
                          const SizedBox(
                            height: 12,
                          ),
                        ]),
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Material(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.deepPurple[400],
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      updCon();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 14),
                      child: AnimatedBuilder(
                        animation: _conAnimation,
                        builder: (context, child) {
                          return Transform.rotate(
                              angle: cast<double>(_conAnimation.value) ?? 0 / 1,
                              child: child);
                        },
                        child: SvgPicture.asset(
                          'assets/icon_update.svg',
                          semanticsLabel: 'update ',
                          height: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Center(
              child: Text(
            '${L('Now open this link', _model.localeAdapter)}\n${L('in any browser', _model.localeAdapter)}',
            style: GoogleFonts.getFont(
              L('Comfortaa', _model.localeAdapter),
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          )),
          Container(
            decoration: BoxDecoration(
              color: Colors.deepPurple[400],
              borderRadius: BorderRadius.circular(12),
            ),
            height: 42,
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 18),
            child: Row(
              children: <Widget>[
                const SizedBox(
                  width: 14,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      ip,
                      // todo remove TextStyle
                      style: GoogleFonts.getFont('Andika',
                          color: Colors.white, fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(
                  width: 6,
                ),
                Material(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.deepPurple[400],
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: ip)).then((result) {
                        final snackBar = SnackBar(
                          backgroundColor: Colors.deepPurple[500],
                          duration: const Duration(seconds: 1),
                          content: Text(
                            L('Copied to Clipboard', _model.localeAdapter),
                            style: GoogleFonts.getFont(
                                L('Andika', _model.localeAdapter),
                                color: Colors.white),
                          ),
                        );
                        Scaffold.of(context).showSnackBar(snackBar);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 12),
                      child: SvgPicture.asset(
                        'assets/icon_copy.svg',
                        semanticsLabel: 'update',
                        width: 16,
                      ),
                    ),
                  ),
                ),
                Material(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.deepPurple[400],
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      updIp(true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 12),
                      child: AnimatedBuilder(
                        animation: _ipAnimation,
                        builder: (context, child) {
                          return Transform.rotate(
                              angle: cast<double>(_ipAnimation.value) ?? 0 / 1,
                              child: child);
                        },
                        child: SvgPicture.asset(
                          'assets/icon_update.svg',
                          semanticsLabel: 'update ',
                          height: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 18),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.deepPurple[300],
            ),
            child: Text(
              '${L('The recipient needs to be connected', _model.localeAdapter)}\n${L('to the same network', _model.localeAdapter)}',
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(L('Andika', _model.localeAdapter),
                  color: Colors.white, fontSize: 18),
            ),
          ),
          SizedBox(
            child: SafeArea(
              top: false,
              right: false,
              left: false,
              child: Container(),
            ),
          )
        ],
      ),
    );
  }
}
