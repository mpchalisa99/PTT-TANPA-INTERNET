export interface FlutterSourceFile {
  path: string;
  title: string;
  category: 'Core UI' | 'UDP Network' | 'Audio Engine' | 'Model & Config';
  description: string;
  code: string;
}

export const FLUTTER_SOURCE_FILES: FlutterSourceFile[] = [
  {
    path: 'lib/main.dart (ALL-IN-ONE)',
    title: 'main.dart (Gabungan Lengkap)',
    category: 'Core UI',
    description:
      'Seluruh arsitektur aplikasi (Model PeerMember, UdpNetworkService, AudioService, dan UI Taktikal) digabung utuh dalam SATU file main.dart.',
    code: `// Lihat atau unduh file gabungan utuh di /flutter_project/lib/main.dart atau salin langsung dari panel ini.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:udp/udp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final audioService = AudioService();
  final udpNetworkService = UdpNetworkService();

  udpNetworkService.onAudioPacketReceived = (Uint8List pcmBytes, String senderIp) {
    audioService.playAudioChunk(pcmBytes);
  };

  await udpNetworkService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UdpNetworkService>.value(value: udpNetworkService),
        Provider<AudioService>.value(value: audioService),
      ],
      child: const DiskomlekauTacticalPttApp(),
    ),
  );
}`,
  },
  {
    path: 'pubspec.yaml',
    title: 'pubspec.yaml',
    category: 'Model & Config',
    description:
      'Konfigurasi environment SDK >=3.0.0 <4.0.0 beserta dependencies flutter, provider, udp, network_info_plus, record, dan audioplayers.',
    code: `name: diskomlekau_tactical_ptt
description: Aplikasi Android Push-to-Talk (PTT) Walkie Talkie Taktikal via LAN/WiFi Hotspot tanpa internet.
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.2
  udp: ^5.0.3
  network_info_plus: ^6.0.1
  record: ^5.1.2
  audioplayers: ^6.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true`,
  },
  {
    path: 'lib/models/peer_member.dart',
    title: 'peer_member.dart',
    category: 'Model & Config',
    description:
      'Class PeerMember dengan properti id, callsign, ipAddress, channel, isTargeted (default true), lastSeen, lastPingMs, serta factory PeerMember.fromJson.',
    code: `class PeerMember {
  final String id;
  String callsign;
  final String ipAddress;
  final int channel;
  bool isTargeted;
  DateTime lastSeen;
  int lastPingMs;

  PeerMember({
    required this.id,
    required this.callsign,
    required this.ipAddress,
    required this.channel,
    this.isTargeted = true,
    this.lastPingMs = 24,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Factory untuk memproses data JSON dari paket UDP Broadcast Auto-Discovery
  factory PeerMember.fromJson(Map<String, dynamic> json) {
    return PeerMember(
      id: (json['id'] ?? json['ip'] ?? 'UNKNOWN').toString(),
      callsign: (json['callsign'] ?? 'PEER').toString().toUpperCase(),
      ipAddress: (json['ip'] ?? '0.0.0.0').toString(),
      channel: (json['ch'] as num?)?.toInt() ?? 12,
      isTargeted: json['isTargeted'] as bool? ?? true,
      lastPingMs: (json['ping'] as num?)?.toInt() ?? 24,
      lastSeen: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'callsign': callsign,
        'ip': ipAddress,
        'ch': channel,
        'isTargeted': isTargeted,
        'ping': lastPingMs,
      };
}`,
  },
  {
    path: 'lib/services/audio_service.dart',
    title: 'audio_service.dart',
    category: 'Audio Engine',
    description:
      'Service perekam & pemutar suara Raw PCM 16-bit 16kHz Mono menggunakan package record dan audioplayers (BytesSource in-memory WAV header) tanpa internet.',
    code: `import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// ============================================================================
/// AUDIO SERVICE - STREAMING SUARA RAW PCM 16-BIT 16KHZ MONO TANPA INTERNET
/// ============================================================================
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<Uint8List>? _recordingSubscription;
  bool _isRecording = false;

  static const int sampleRate = 16000;
  static const int numChannels = 1;
  static const int bitsPerSample = 16;

  /// 1280 bytes = 40ms audio @ 16kHz 16-bit mono (aman di bawah MTU WiFi 1472B)
  static const int udpChunkSize = 1280;

  final BytesBuilder _playbackBuffer = BytesBuilder(copy: false);
  bool _isPlayingChunk = false;

  AudioService() {
    _player.setReleaseMode(ReleaseMode.stop);
    _player.setPlayerMode(PlayerMode.lowLatency);
  }

  /// 1 & 2. Mulai menangkap suara microphone (PCM 16-bit Mono 16000Hz) dan
  /// mengalirkan byte audio secara terus-menerus ke callback [onAudioChunk].
  Future<void> startRecording(void Function(Uint8List chunk) onAudioChunk) async {
    if (_isRecording) return;

    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      debugPrint('Izin microphone belum diberikan.');
      return;
    }

    _isRecording = true;
    final List<int> accumulator = [];

    final Stream<Uint8List> micStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );

    _recordingSubscription = micStream.listen(
      (Uint8List rawBytes) {
        if (!_isRecording) return;
        accumulator.addAll(rawBytes);

        while (accumulator.length >= udpChunkSize) {
          final chunk = Uint8List.fromList(accumulator.sublist(0, udpChunkSize));
          accumulator.removeRange(0, udpChunkSize);
          onAudioChunk(chunk);
        }
      },
      onError: (Object err) {
        debugPrint('Error pada stream microphone: \$err');
      },
    );
  }

  /// 3. Menghentikan perekaman microphone.
  Future<void> stopRecording() async {
    _isRecording = false;
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  /// 4. Memutar data PCM mentah yang diterima dari jaringan UDP di memori RAM.
  Future<void> playAudioChunk(Uint8List pcmBytes) async {
    if (pcmBytes.isEmpty || _isRecording) return;

    _playbackBuffer.add(pcmBytes);

    if (_playbackBuffer.length < udpChunkSize * 3 || _isPlayingChunk) {
      return;
    }

    _isPlayingChunk = true;
    try {
      final rawPcm = _playbackBuffer.takeBytes();
      final wavBytes = _addWavHeader(rawPcm);
      await _player.play(BytesSource(wavBytes));
    } catch (e) {
      debugPrint('Gagal memutar chunk audio UDP: \$e');
    } finally {
      _isPlayingChunk = false;
    }
  }

  /// Membungkus Raw PCM 16-bit 16kHz Mono dengan header WAV 44-byte di RAM
  Uint8List _addWavHeader(Uint8List pcmData) {
    final int dataLength = pcmData.length;
    final int fileSize = dataLength + 36;
    final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final int blockAlign = numChannels * (bitsPerSample ~/ 8);

    final header = ByteData(44);
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataLength, Endian.little);

    final wavBuffer = Uint8List(44 + dataLength);
    wavBuffer.setRange(0, 44, header.buffer.asUint8List());
    wavBuffer.setRange(44, 44 + dataLength, pcmData);
    return wavBuffer;
  }

  Future<void> dispose() async {
    await stopRecording();
    await _recorder.dispose();
    await _player.dispose();
  }
}`,
  },
  {
    path: 'lib/main.dart',
    title: 'main.dart',
    category: 'Core UI',
    description:
      'Entry point MultiProvider dan UI utama TACTICAL NET-COMM SUBDISRUDAL yang otomatis me-refresh saat ada perangkat baru terhubung ke Hotspot.',
    code: `import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/peer_member.dart';
import 'services/audio_service.dart';
import 'services/udp_network_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final audioService = AudioService();
  final udpNetworkService = UdpNetworkService();

  udpNetworkService.onAudioPacketReceived = (pcmBytes, senderIp) {
    audioService.playAudioChunk(pcmBytes);
  };

  await udpNetworkService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UdpNetworkService>.value(
          value: udpNetworkService,
        ),
        Provider<AudioService>.value(
          value: audioService,
        ),
      ],
      child: const DiskomlekauTacticalPttApp(),
    ),
  );
}

class DiskomlekauTacticalPttApp extends StatelessWidget {
  const DiskomlekauTacticalPttApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TACTICAL NET-COMM SUBDISRUDAL',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF60A5FA),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const TacticalPttHomePage(),
    );
  }
}

class TacticalPttHomePage extends StatefulWidget {
  const TacticalPttHomePage({super.key});

  @override
  State<TacticalPttHomePage> createState() => _TacticalPttHomePageState();
}

class _TacticalPttHomePageState extends State<TacticalPttHomePage> {
  int _selectedNavIndex = 0;

  static const Color bgDarkNavy = Color(0xFF0F172A);
  static const Color cyanBright = Color(0xFF3B82F6);
  static const Color cyanSoft = Color(0xFF94A3B8);

  final List<PeerMember> _fallbackMembers = [
    PeerMember(id: 'M1', callsign: 'YUDHI', ipAddress: '192.168.43.1', channel: 12),
    PeerMember(id: 'M2', callsign: 'EKO', ipAddress: '192.168.43.102', channel: 12),
    PeerMember(id: 'M3', callsign: 'PUJI', ipAddress: '192.168.43.103', channel: 12),
    PeerMember(id: 'M4', callsign: 'JEFRY', ipAddress: '192.168.43.104', channel: 12),
    PeerMember(id: 'M5', callsign: 'YUSUF', ipAddress: '192.168.43.105', channel: 12),
    PeerMember(id: 'M6', callsign: 'EDWIN', ipAddress: '192.168.43.106', channel: 12),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<UdpNetworkService>(
      builder: (context, net, _) {
        final audioService = context.read<AudioService>();
        final List<PeerMember> peers = net.activeChannelPeers.isNotEmpty
            ? net.activeChannelPeers
            : _fallbackMembers;
        final int activeCount = peers.length;

        return Scaffold(
          backgroundColor: bgDarkNavy,
          body: CustomPaint(
            painter: _TacticalGridPainter(),
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Column(
                        children: [
                          // 1. Teks judul "TACTICAL NET-COMM SUBDISRUDAL"
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'TACTICAL NET-COMM SUBDISRUDAL',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFE5FAFF),
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                shadows: [Shadow(color: cyanBright, blurRadius: 14)],
                              ),
                            ),
                          ),

                          // 2. Container Card Status Jaringan
                          _buildNetworkStatusCard(net, activeCount),
                          const SizedBox(height: 12),

                          // 3. Container Channel Selector
                          _buildChannelCard(net, activeCount),
                          const SizedBox(height: 14),

                          // 4. GridView Anggota
                          _buildMemberGridSection(net, peers),
                          const SizedBox(height: 18),

                          // 5. Tombol PTT Raksasa (GestureDetector)
                          _buildGiantPttButton(net, audioService),
                          const SizedBox(height: 16),

                          _buildBottomStatusBanner(net),
                        ],
                      ),
                    ),
                  ),

                  // 6. Bottom Navigation Bar (4 Ikon)
                  _buildBottomNavigationBar(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNetworkStatusCard(UdpNetworkService net, int activeCount) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _tacticalCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PING: \${net.lastPingMs} ms',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
              ),
              Text(
                net.isHighLatency ? 'LATENCY TINGGI' : 'LATENCY RENDAH',
                style: const TextStyle(color: cyanSoft, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              InkWell(
                onTap: net.refreshPing,
                child: const Icon(Icons.sync, size: 18, color: cyanBright),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: cyanBright,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  net.localIp.endsWith('.1') ? 'MASTER HOST' : 'CLIENT',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: cyanBright.withValues(alpha: 0.3), height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '\${net.localIp.endsWith(".1") ? "PERAN: MASTER HOST" : "PERAN: CLIENT"} (\${net.localIp})',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'Peer Aktif: \$activeCount',
                style: const TextStyle(color: cyanSoft, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelCard(UdpNetworkService net, int activeCount) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _tacticalCardDecoration(),
      child: Column(
        children: [
          const Text(
            'CHANNEL SELECTOR - CLOUD & HOTSPOT SYNC',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                onPressed: () => net.setChannel(net.currentChannel - 1),
                icon: const Icon(Icons.chevron_left, color: cyanBright, size: 32),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF021629),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cyanBright.withValues(alpha: 0.45)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'CHANNEL \${net.currentChannel.toString().padLeft(2, "0")}',
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'MASTER HOST - \${net.localIp}',
                        style: const TextStyle(color: cyanSoft, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () => net.setChannel(net.currentChannel + 1),
                icon: const Icon(Icons.chevron_right, color: cyanBright, size: 32),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'HP MASTER AKTIF | \$activeCount MEMBERS ONLINE',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberGridSection(UdpNetworkService net, List<PeerMember> peers) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: peers.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.15,
      ),
      itemBuilder: (context, index) {
        final peer = peers[index];
        return InkWell(
          onTap: () => net.togglePeerTarget(peer.ipAddress),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: peer.isTargeted
                    ? [const Color(0xFF1499C7), const Color(0xFF0A6691)]
                    : [const Color(0xFF062C4D), const Color(0xFF041D35)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cyanBright),
            ),
            child: Row(
              children: [
                const Icon(Icons.mic_none, size: 18, color: cyanBright),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peer.callsign,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                      const Text(
                        'ALL AKTIF',
                        style: TextStyle(color: cyanSoft, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGiantPttButton(UdpNetworkService net, AudioService audioService) {
    final bool isTx = net.isTransmitting;
    return GestureDetector(
      onLongPress: () async {
        net.setTransmitting(true);
        await audioService.startRecording((pcmChunk) {
          net.sendRawAudioChunk(pcmChunk);
        });
      },
      onLongPressEnd: (_) async {
        await audioService.stopRecording();
        net.setTransmitting(false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 210,
        height: 210,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: isTx
                ? [cyanBright, const Color(0xFF087CA6), const Color(0xFF042D4A)]
                : [const Color(0xFF1476A6), const Color(0xFF073A5E), const Color(0xFF031F36)],
          ),
          border: Border.all(color: cyanBright, width: isTx ? 4 : 2.5),
          boxShadow: [
            BoxShadow(
              color: cyanBright.withValues(alpha: isTx ? 0.75 : 0.35),
              blurRadius: isTx ? 42 : 24,
              spreadRadius: isTx ? 6 : 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'PUSH TO TALK & HOLD',
              style: TextStyle(color: Color(0xFF03233B), fontSize: 11, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Icon(Icons.sensors, size: 44, color: isTx ? Colors.white : const Color(0xFF03233B)),
            const SizedBox(height: 6),
            Text(
              isTx ? 'TRANSMITTING' : 'MASTER READY',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStatusBanner(UdpNetworkService net) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF28E0FF), Color(0xFF09B6DF)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        net.isTransmitting ? 'TRANSMITTING RAW PCM UDP...' : 'MASTER READY',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    final items = [
      (Icons.sensors, '[Channels]'),
      (Icons.edit_outlined, '[Edit Nama]'),
      (Icons.qr_code_2, '[Barcode]'),
      (Icons.settings_outlined, '[Settings]'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: const Color(0xFF031729),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final isSelected = _selectedNavIndex == i;
          return InkWell(
            onTap: () => setState(() => _selectedNavIndex = i),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(items[i].\$1, color: isSelected ? cyanBright : Colors.white, size: 22),
                const SizedBox(height: 4),
                Text(
                  items[i].\$2,
                  style: TextStyle(
                    color: isSelected ? cyanBright : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  BoxDecoration _tacticalCardDecoration() {
    return BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF334155), width: 1.4),
    );
  }
}

class _TacticalGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF23DCFF).withValues(alpha: 0.06)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}`,
  },
  {
    path: 'lib/services/udp_network_service.dart',
    title: 'udp_network_service.dart (Port 50500 Offline Broadcast)',
    category: 'UDP Network',
    description:
      'Service Komunikasi Broadcast UDP 100% Offline (Hotspot Master & Client) pada Port Tetap 50500 dengan deteksi otomatis IP Broadcast (x.x.x.255) & filter Anti-Echo IP sendiri.',
    code: `import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:udp/udp.dart';

class UdpNetworkService extends ChangeNotifier {
  /// 1. Port tetap (Fixed Port) untuk komunikasi Broadcast UDP Audio PTT
  static const int pttPort = 50500;
  static const String masterDefaultIp = '192.168.43.1';
  static const String defaultBroadcastIp = '192.168.43.255';

  UDP? _udpSocket;
  String _localIp = masterDefaultIp;
  String _broadcastIp = defaultBroadcastIp;
  final Set<String> _localInterfaceIps = {masterDefaultIp, '127.0.0.1'};

  /// 4. Callback saat paket Raw PCM diterima dari perangkat lain (bukan IP sendiri)
  void Function(Uint8List pcmBytes, String senderIp)? onAudioPacketReceived;

  String get localIp => _localIp;
  String get broadcastIp => _broadcastIp;
  bool get isMaster => _localIp.trim().endsWith('.1');
  String get roleStatusText =>
      _localIp.trim().endsWith('.1') ? 'PERAN: MASTER HOST' : 'PERAN: CLIENT';

  /// Inisialisasi: Deteksi IP Broadcast WiFi/Hotspot & buka UDP Receiver di port 50500
  Future<void> initialize() async {
    await detectBroadcastIp();
    await _startUdpReceiver();
  }

  /// 2. Deteksi IP Lokal & Hitung IP Broadcast Jaringan WiFi/Hotspot Saat Ini
  /// Contoh: Jika IP HP 192.168.43.5 -> Broadcast ke 192.168.43.255
  Future<String> detectBroadcastIp() async {
    String? detectedLocalIp;
    String? detectedBroadcast;
    final Set<String> foundIps = {'127.0.0.1'};

    try {
      final info = NetworkInfo();

      // a) Ambil IP WiFi dari network_info_plus (berfungsi saat HP menjadi Client)
      final wifiIp = await info.getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '0.0.0.0') {
        detectedLocalIp = wifiIp;
        foundIps.add(wifiIp);
      }

      final wifiBroadcast = await info.getWifiBroadcast();
      if (wifiBroadcast != null &&
          wifiBroadcast.isNotEmpty &&
          wifiBroadcast != '0.0.0.0' &&
          wifiBroadcast != '255.255.255.255') {
        detectedBroadcast = wifiBroadcast;
      }

      // b) Fallback NetworkInterface.list (WAJIB untuk HP Master Hotspot karena
      //    saat menyalakan Hotspot tanpa WiFi, IP berada di interface ap0/wlan0/swlan0)
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isHotspotOrWifi = name.contains('ap') ||
            name.contains('wlan') ||
            name.contains('swlan') ||
            name.contains('rndis');

        for (final addr in iface.addresses) {
          final ip = addr.address;
          foundIps.add(ip);

          if (ip == masterDefaultIp) {
            detectedLocalIp = masterDefaultIp;
          } else if (isHotspotOrWifi &&
              (ip.startsWith('192.168.') ||
                  ip.startsWith('172.') ||
                  ip.startsWith('10.'))) {
            detectedLocalIp ??= ip;
          } else if (detectedLocalIp == null && ip.startsWith('192.168.')) {
            detectedLocalIp = ip;
          }
        }
      }
    } catch (e) {
      debugPrint('Gagal mendeteksi IP jaringan: \$e');
    }

    _localIp = (detectedLocalIp != null && detectedLocalIp.isNotEmpty)
        ? detectedLocalIp
        : masterDefaultIp;
    foundIps.add(_localIp);

    _localInterfaceIps
      ..clear()
      ..addAll(foundIps);

    // Ubah oktet terakhir IPv4 menjadi .255 (misal: 192.168.43.5 -> 192.168.43.255)
    final parts = _localIp.split('.');
    if (parts.length == 4) {
      _broadcastIp = '\${parts[0]}.\${parts[1]}.\${parts[2]}.255';
    } else {
      _broadcastIp = detectedBroadcast ?? defaultBroadcastIp;
    }

    notifyListeners();
    return _broadcastIp;
  }

  /// 3. UDP Sender: Mengirim (Broadcast) Raw PCM Audio (Uint8List) ke IP Broadcast
  Future<void> broadcastRawPcmAudio(Uint8List pcmBytes) async {
    if (_udpSocket == null || pcmBytes.isEmpty) return;

    try {
      // Pastikan flag broadcast socket aktif sebelum mengirim ke x.x.x.255
      _udpSocket!.socket?.broadcastEnabled = true;

      final broadcastEndpoint = Endpoint.unicast(
        InternetAddress(_broadcastIp),
        port: const Port(pttPort),
      );

      await _udpSocket!.send(pcmBytes, broadcastEndpoint);
    } catch (e) {
      debugPrint('Gagal mengirim UDP broadcast audio ke \$_broadcastIp:\$pttPort -> \$e');
    }
  }

  /// 4. UDP Receiver: Mendengarkan Port 50500 terus-menerus & filter IP sendiri (Anti-Echo)
  Future<void> _startUdpReceiver() async {
    try {
      _udpSocket?.close();
      _udpSocket = await UDP.bind(Endpoint.any(port: const Port(pttPort)));
      _udpSocket!.socket?.broadcastEnabled = true;

      _udpSocket!.asStream().listen(
        (Datagram? datagram) {
          if (datagram == null || datagram.data.isEmpty) return;

          final String senderIp = datagram.address.address;

          // Abaikan paket yang berasal dari IP perangkat sendiri agar tidak terjadi Echo
          if (_isOwnIp(senderIp)) return;

          // Picu callback dengan data Raw PCM (Uint8List) dan IP pengirim
          onAudioPacketReceived?.call(datagram.data, senderIp);
        },
        onError: (Object error) {
          debugPrint('Error pada UDP Receiver port \$pttPort: \$error');
        },
      );
    } catch (e) {
      debugPrint('Gagal bind UDP Receiver di port \$pttPort: \$e');
    }
  }

  bool _isOwnIp(String senderIp) {
    return senderIp == _localIp ||
        senderIp == '127.0.0.1' ||
        senderIp == '0.0.0.0' ||
        _localInterfaceIps.contains(senderIp);
  }

  @override
  void dispose() {
    _udpSocket?.close();
    super.dispose();
  }
}`,
  },
  {
    path: 'android/app/src/main/AndroidManifest.xml',
    title: 'AndroidManifest.xml (Izin LAN Offline & UDP Broadcast)',
    category: 'Model & Config',
    description:
      'Konfigurasi lengkap izin Android untuk komunikasi UDP Broadcast lokal 100% offline via Mobile Hotspot & WiFi tanpa internet.',
    code: `<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="id.mil.tni_au.diskomlekau.tactical_ptt">

    <!-- 1. Izin membuka RawDatagramSocket (UDP Port 50500) di jaringan lokal -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <!-- 2. Izin membaca status WiFi & Subnet lokal (network_info_plus) -->
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />

    <!-- 3. WAJIB untuk menerima paket UDP Broadcast (x.x.x.255) & Multicast di Android -->
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />

    <!-- 4. Izin membaca info jaringan WiFi di Android 8.1 - 12 & Android 13+ -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission
        android:name="android.permission.NEARBY_WIFI_DEVICES"
        android:usesPermissionFlags="neverForLocation" />

    <!-- 5. Izin rekam suara PTT & menjaga CPU tetap hidup saat layar mati -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <application
        android:label="DISKOMLEKAU TACTICAL PTT"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <!-- Activity Configuration -->
    </application>
</manifest>`,
  },
];

