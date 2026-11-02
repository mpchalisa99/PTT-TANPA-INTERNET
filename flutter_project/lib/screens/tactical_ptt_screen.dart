import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/peer_member.dart';
import '../services/audio_ptt_service.dart';
import '../services/udp_network_service.dart';

class TacticalPttScreen extends StatefulWidget {
  final UdpNetworkService networkService;
  final AudioPttService audioService;

  const TacticalPttScreen({
    super.key,
    required this.networkService,
    required this.audioService,
  });

  @override
  State<TacticalPttScreen> createState() => _TacticalPttScreenState();
}

class _TacticalPttScreenState extends State<TacticalPttScreen> {
  int _selectedNavIndex = 0;

  /// State IP & Teks Status Peran Perangkat dari `network_info_plus`
  String _currentIp = '0.0.0.0';
  String _roleStatusText = 'PERAN: CLIENT';

  final List<PeerMember> _mockMembers = [
    PeerMember(id: 'M1', callsign: 'YUDHI', ipAddress: '192.168.43.1', channel: 12, isMaster: true),
    PeerMember(id: 'M2', callsign: 'EKO', ipAddress: '192.168.43.102', channel: 12),
    PeerMember(id: 'M3', callsign: 'PUJI', ipAddress: '192.168.43.103', channel: 12),
    PeerMember(id: 'M4', callsign: 'JEFRY', ipAddress: '192.168.43.104', channel: 12),
    PeerMember(id: 'M5', callsign: 'YUSUF', ipAddress: '192.168.43.105', channel: 12),
    PeerMember(id: 'M6', callsign: 'EDWIN', ipAddress: '192.168.43.106', channel: 12),
  ];

  /// ==========================================================================
  /// PALET WARNA TEMA BIRU & GREY MODERN (MODERN BLUE & SLATE GREY)
  /// ==========================================================================
  static const Color bgSlateDark = Color(0xFF0F172A);     // Slate 900 (Background Utama)
  static const Color panelSlateGrey = Color(0xFF1E293B);  // Slate 800 (Card / Panel Surface)
  static const Color surfaceSlate = Color(0xFF0B1120);    // Deep Slate Surface
  static const Color borderSlateGrey = Color(0xFF334155); // Slate 700 (Border Grey Modern)
  static const Color textGreyMuted = Color(0xFF94A3B8);   // Slate 400 (Secondary Grey Text)
  static const Color bluePrimary = Color(0xFF3B82F6);     // Blue 500 (Royal Blue Modern)
  static const Color blueDeep = Color(0xFF2563EB);        // Blue 600 (Deep Blue Accent)
  static const Color blueSoft = Color(0xFF60A5FA);        // Blue 400 (Soft Blue Highlight)

  @override
  void initState() {
    super.initState();
    _detectDeviceRoleWithNetworkInfoPlus();
  }

  /// Mendapatkan IP saat ini menggunakan `network_info_plus`:
  /// - Jika IP berakhiran `.1`, tampilkan `'PERAN: MASTER HOST'`
  /// - Jika bukan, tampilkan `'PERAN: CLIENT'`
  Future<void> _detectDeviceRoleWithNetworkInfoPlus() async {
    final info = NetworkInfo();
    String? wifiIp;

    try {
      wifiIp = await info.getWifiIP();
    } catch (_) {}

    final resolvedIp = (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '0.0.0.0')
        ? wifiIp.trim()
        : widget.networkService.localIp.trim();

    final isMasterHost = resolvedIp.endsWith('.1');

    if (!mounted) return;
    setState(() {
      _currentIp = resolvedIp;
      _roleStatusText = isMasterHost ? 'PERAN: MASTER HOST' : 'PERAN: CLIENT';
    });
  }

  List<PeerMember> get _displayMembers {
    final discovered = widget.networkService.activeChannelPeers;
    if (discovered.isNotEmpty) return discovered;
    return _mockMembers;
  }

  void _showEditCallsignDialog({PeerMember? targetMember}) {
    final controller = TextEditingController(
      text: targetMember != null
          ? targetMember.callsign
          : widget.networkService.myCallsign,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panelSlateGrey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: bluePrimary, width: 1.5),
        ),
        title: Text(
          targetMember != null ? 'UBAH CALLSIGN ANGGOTA' : 'EDIT CALLSIGN SAYA',
          style: const TextStyle(color: blueSoft, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'Masukkan Nama / Callsign',
            hintStyle: const TextStyle(color: textGreyMuted),
            filled: true,
            fillColor: bgSlateDark,
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: borderSlateGrey),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: bluePrimary, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('BATAL', style: TextStyle(color: textGreyMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: bluePrimary),
            onPressed: () {
              final val = controller.text.trim().toUpperCase();
              if (val.isNotEmpty) {
                setState(() {
                  if (targetMember != null) {
                    targetMember.callsign = val;
                  } else {
                    widget.networkService.setCallsign(val);
                    _mockMembers[0].callsign = val;
                  }
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('SIMPAN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showBarcodeDialog() {
    final net = widget.networkService;
    final payload = 'DISKOMLEKAU://JOIN?host=${net.localIp}&ch=${net.currentChannel}&port=50500';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panelSlateGrey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: bluePrimary, width: 1.5),
        ),
        title: const Text(
          'BARCODE SINKRONISASI HOTSPOT',
          textAlign: TextAlign.center,
          style: TextStyle(color: blueSoft, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.qr_code_2, size: 170, color: bgSlateDark),
            ),
            const SizedBox(height: 12),
            Text(
              'CH ${net.currentChannel} • HOST ${net.localIp}:50500',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              payload,
              textAlign: TextAlign.center,
              style: const TextStyle(color: textGreyMuted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('TUTUP', style: TextStyle(color: blueSoft, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.networkService,
      builder: (context, _) {
        final net = widget.networkService;
        final members = _displayMembers;
        final activeClientsCount = members.length > 1 ? members.length - 1 : 3;

        // Evaluasi IP real-time: Jika IP berakhiran '.1' -> 'PERAN: MASTER HOST', selain itu -> 'PERAN: CLIENT'
        final activeIp = (_currentIp != '0.0.0.0' && _currentIp.isNotEmpty)
            ? _currentIp
            : net.localIp;
        final bool isMasterHost = activeIp.trim().endsWith('.1');
        final String roleText = isMasterHost ? 'PERAN: MASTER HOST' : 'PERAN: CLIENT';

        return Scaffold(
          backgroundColor: bgSlateDark,
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
                          // 1. HEADER TEKS
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'TACTICAL NET-COMM SUBDISRUDAL',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFF8FAFC),
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                                shadows: [
                                  Shadow(color: bluePrimary, blurRadius: 14),
                                ],
                              ),
                            ),
                          ),

                          // 2. CARD STATUS JARINGAN & PERAN PERANGKAT (TOP PANEL)
                          _buildNetworkStatusCard(net, activeClientsCount, activeIp, isMasterHost, roleText),
                          const SizedBox(height: 12),

                          // 3. CARD CHANNEL SELECTOR
                          _buildChannelSelectorCard(net, members.length, activeIp, roleText),
                          const SizedBox(height: 14),

                          // 4. GRID USER / ANGGOTA
                          _buildMembersSection(net, members),
                          const SizedBox(height: 18),

                          // 5. TOMBOL PTT UTAMA (CENTER)
                          _buildCenterPttButton(net, isMasterHost),
                          const SizedBox(height: 16),

                          // STATUS BANNER BAWAH TOMBOL PTT
                          _buildMasterReadyBanner(net, roleText),
                        ],
                      ),
                    ),
                  ),

                  // 6. BOTTOM NAVIGATION BAR
                  _buildBottomNavBar(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNetworkStatusCard(
    UdpNetworkService net,
    int activeClients,
    String activeIp,
    bool isMasterHost,
    String roleText,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _tacticalCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Indikator Sinyal 4 Bar (Biru & Grey Modern)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: bgSlateDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderSlateGrey),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _signalBar(8, true),
                    const SizedBox(width: 3),
                    _signalBar(12, true),
                    const SizedBox(width: 3),
                    _signalBar(16, true),
                    const SizedBox(width: 3),
                    _signalBar(20, !net.isHighLatency),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // PING: [X] ms
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PING:',
                    style: TextStyle(color: textGreyMuted, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  Text(
                    '${net.lastPingMs} ms',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Text(
                '(+${net.pingDeltaMs.abs()}ms)',
                style: const TextStyle(color: blueSoft, fontSize: 12),
              ),
              const SizedBox(width: 8),
              // Status LATENCY TINGGI / RENDAH
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: bgSlateDark.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderSlateGrey),
                  ),
                  child: Text(
                    net.isHighLatency ? 'LATENCY\nTINGGI' : 'LATENCY\nRENDAH',
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontWeight: FontWeight.bold,
                      fontSize: 10.5,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Tombol Refresh Ping & Cek Ulang IP
              InkWell(
                onTap: () {
                  net.refreshPing();
                  _detectDeviceRoleWithNetworkInfoPlus();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: bgSlateDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: bluePrimary.withValues(alpha: 0.6)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.sync, size: 15, color: blueSoft),
                      SizedBox(width: 4),
                      Text('Ping', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Badge Status Peran (MASTER HOST vs CLIENT)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isMasterHost
                        ? [bluePrimary, blueDeep]
                        : [const Color(0xFF475569), const Color(0xFF334155)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: (isMasterHost ? bluePrimary : borderSlateGrey).withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      isMasterHost ? Icons.star : Icons.devices,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isMasterHost ? 'MASTER HOST' : 'CLIENT',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: borderSlateGrey, height: 1),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Menampilkan teks 'PERAN: MASTER HOST' jika IP berakhiran '.1', atau 'PERAN: CLIENT' jika bukan
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roleText,
                      style: TextStyle(
                        color: isMasterHost ? blueSoft : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'IP: $activeIp • Broadcast: ${net.broadcastIp}',
                      style: const TextStyle(
                        color: textGreyMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  'Peer Aktif: $activeClients • Port: ${UdpNetworkService.pttPort}\n(UDP Broadcast Offline)',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: textGreyMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelSelectorCard(
    UdpNetworkService net,
    int membersCount,
    String activeIp,
    String roleText,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _tacticalCardDecoration(),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.arrow_drop_down, color: blueSoft, size: 18),
              Text(
                'CHANNEL SELECTOR - HOTSPOT LAN SYNC',
                style: TextStyle(
                  color: textGreyMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
              Icon(Icons.arrow_drop_down, color: blueSoft, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildRotaryKnob(
                onTap: () => net.setChannel(net.currentChannel - 1),
                angle: -math.pi / 4,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  decoration: BoxDecoration(
                    color: surfaceSlate,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderSlateGrey, width: 1.5),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'CHANNEL ${net.currentChannel.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$roleText • $activeIp',
                        style: const TextStyle(
                          color: blueSoft,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildRotaryKnob(
                onTap: () => net.setChannel(net.currentChannel + 1),
                angle: math.pi / 4,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$roleText | $membersCount MEMBERS ONLINE',
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  letterSpacing: 0.4,
                ),
              ),
              InkWell(
                onTap: _showBarcodeDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: bgSlateDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: bluePrimary.withValues(alpha: 0.65)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.qr_code_2, size: 16, color: blueSoft),
                      SizedBox(width: 5),
                      Text(
                        'BARCODE',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRotaryKnob({required VoidCallback onTap, required double angle}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFF334155), Color(0xFF0F172A)],
          ),
          border: Border.all(color: bluePrimary.withValues(alpha: 0.7), width: 2),
          boxShadow: [BoxShadow(color: bluePrimary.withValues(alpha: 0.25), blurRadius: 8)],
        ),
        child: Center(
          child: Transform.rotate(
            angle: angle,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: blueSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMembersSection(UdpNetworkService net, List<PeerMember> members) {
    return Column(
      children: [
        Row(
          children: [
            InkWell(
              onTap: net.toggleTalkAll,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: net.talkAll
                        ? [bluePrimary, blueDeep]
                        : [panelSlateGrey, bgSlateDark],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: net.talkAll ? blueSoft : borderSlateGrey, width: 1.5),
                  boxShadow: [
                    if (net.talkAll)
                      BoxShadow(color: bluePrimary.withValues(alpha: 0.45), blurRadius: 14),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.sensors,
                      size: 18,
                      color: net.talkAll ? Colors.white : blueSoft,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'TALK ALL',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: _tacticalCardDecoration(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: RichText(
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: const TextStyle(fontSize: 13, color: textGreyMuted),
                          children: [
                            const TextSpan(text: 'ID SAYA: '),
                            TextSpan(
                              text: net.myCallsign,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _showEditCallsignDialog(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: bgSlateDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderSlateGrey),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.edit, size: 13, color: blueSoft),
                            SizedBox(width: 4),
                            Text('Edit Nama', style: TextStyle(color: Colors.white, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: members.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.15,
          ),
          itemBuilder: (ctx, index) {
            final member = members[index];
            final isHighlighted = member.isTalking || member.isTargeted;
            return InkWell(
              onTap: () {
                setState(() {
                  member.isTargeted = !member.isTargeted;
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isHighlighted
                        ? [const Color(0xFF1E3A8A), panelSlateGrey]
                        : [panelSlateGrey, bgSlateDark],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: member.isTargeted ? bluePrimary : borderSlateGrey,
                    width: member.isTargeted ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bgSlateDark,
                        border: Border.all(color: borderSlateGrey),
                      ),
                      child: const Icon(Icons.mic_none, size: 16, color: blueSoft),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.callsign,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            member.ipAddress.endsWith('.1') ? 'MASTER .1' : 'CLIENT',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: textGreyMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => _showEditCallsignDialog(targetMember: member),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: borderSlateGrey),
                        ),
                        child: const Icon(Icons.edit, size: 12, color: textGreyMuted),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCenterPttButton(UdpNetworkService net, bool isMasterHost) {
    final isTx = net.isTransmitting;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildSideWaveform(isTx, reversed: true),
        const SizedBox(width: 12),
        GestureDetector(
          onLongPress: () => widget.audioService.startPushToTalk(),
          onLongPressEnd: (_) => widget.audioService.stopPushToTalk(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 215,
            height: 215,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: isTx
                    ? [blueSoft, bluePrimary, blueDeep]
                    : [const Color(0xFF334155), panelSlateGrey, bgSlateDark],
              ),
              border: Border.all(color: isTx ? blueSoft : bluePrimary, width: isTx ? 4 : 2.5),
              boxShadow: [
                BoxShadow(
                  color: bluePrimary.withValues(alpha: isTx ? 0.65 : 0.28),
                  blurRadius: isTx ? 42 : 24,
                  spreadRadius: isTx ? 6 : 1,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 190,
                  height: 190,
                  child: CustomPaint(
                    painter: _CurvedTextPainter(text: 'PUSH TO TALK & HOLD'),
                  ),
                ),
                Container(
                  width: 142,
                  height: 142,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: isTx
                          ? [bluePrimary, const Color(0xFF1D4ED8)]
                          : [panelSlateGrey, surfaceSlate],
                    ),
                    border: Border.all(color: blueSoft.withValues(alpha: 0.65), width: 1.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.sensors,
                        size: 44,
                        color: isTx ? Colors.white : blueSoft,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isTx
                            ? 'TRANSMITTING'
                            : (isMasterHost ? 'MASTER HOST' : 'CLIENT READY'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        _buildSideWaveform(isTx, reversed: false),
      ],
    );
  }

  Widget _buildSideWaveform(bool active, {required bool reversed}) {
    final heights = [4.0, 5.0, 6.0, 7.0, 8.0, 10.0, 12.0, 14.0];
    final list = reversed ? heights : heights.reversed.toList();
    return Row(
      children: list
          .map(
            (h) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.8),
              width: 3.5,
              height: active ? h * 1.6 : h,
              decoration: BoxDecoration(
                color: active ? blueSoft : borderSlateGrey,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMasterReadyBanner(UdpNetworkService net, String roleText) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [bluePrimary, blueDeep],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: bluePrimary.withValues(alpha: 0.35), blurRadius: 16),
        ],
      ),
      child: Text(
        net.isTransmitting
            ? 'UDP AUDIO STREAMING (PORT ${UdpNetworkService.pttPort})...'
            : '$roleText • SIAP TRANSMISI',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    final items = [
      (Icons.sensors, '[Channels]'),
      (Icons.edit_outlined, '[Edit Nama]'),
      (Icons.qr_code_2, '[Barcode]'),
      (Icons.settings_outlined, '[Settings]'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: surfaceSlate,
        border: Border(top: BorderSide(color: borderSlateGrey)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final selected = _selectedNavIndex == i;
          return InkWell(
            onTap: () {
              setState(() => _selectedNavIndex = i);
              if (i == 1) _showEditCallsignDialog();
              if (i == 2) _showBarcodeDialog();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(items[i].$1, color: selected ? blueSoft : textGreyMuted, size: 22),
                const SizedBox(height: 4),
                Text(
                  items[i].$2,
                  style: TextStyle(
                    color: selected ? Colors.white : textGreyMuted,
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

  Widget _signalBar(double height, bool active) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: active ? blueSoft : borderSlateGrey,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  BoxDecoration _tacticalCardDecoration() {
    return BoxDecoration(
      gradient: const LinearGradient(
        colors: [panelSlateGrey, Color(0xFF152033)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderSlateGrey, width: 1.4),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 14),
      ],
    );
  }
}

/// Painter untuk menggambar teks melingkar "PUSH TO TALK & HOLD"
class _CurvedTextPainter extends CustomPainter {
  final String text;
  const _CurvedTextPainter({required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 14;
    final center = Offset(size.width / 2, size.height / 2);
    const totalArc = math.pi * 0.68;
    const startAngle = -math.pi / 2 - totalArc / 2;
    final charStep = totalArc / (text.length - 1);

    for (int i = 0; i < text.length; i++) {
      final angle = startAngle + i * charStep;
      final charOffset = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );

      canvas.save();
      canvas.translate(charOffset.dx, charOffset.dy);
      canvas.rotate(angle + math.pi / 2);

      final tp = TextPainter(
        text: TextSpan(
          text: text[i],
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Painter untuk motif grid transparan pada latar belakang Slate Grey & Blue Modern
class _TacticalGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.08)
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
}
