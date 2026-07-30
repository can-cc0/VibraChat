import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Firebase konfigürasyonu
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibraChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: FirebaseAuth.instance.currentUser == null
          ? const AuthScreen()
          : const ChatScreen(),
    );
  }
}

// ---------------------------------------------------------
// 1. GİRİŞ / KAYIT EKRANI
// ---------------------------------------------------------
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLogin = true;

  Future<void> submit() async {
    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        UserCredential res = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        // Kullanıcıyı Firestore'a kaydet
        await FirebaseFirestore.instance.collection('users').doc(res.user!.uid).set({
          'email': _emailController.text.trim(),
          'uid': res.user!.uid,
        });
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ChatScreen()));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Giriş Yap' : 'Kayıt Ol')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'E-posta')),
            TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre')),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: submit, child: Text(isLogin ? 'Giriş' : 'Kayıt Ol')),
            TextButton(
              onPressed: () => setState(() => isLogin = !isLogin),
              child: Text(isLogin ? 'Hesabın yok mu? Kayıt Ol' : 'Zaten hesabın var mı? Giriş Yap'),
            )
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// 2. SOHBET VE FOTOĞRAF GÖNDERME EKRANI
// ---------------------------------------------------------
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final currentUser = FirebaseAuth.instance.currentUser;

  // Fotoğraf Seç ve Firebase Storage'a Yükle
  Future<void> sendImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

    if (pickedFile != null) {
      File file = File(pickedFile.path);
      String fileName = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Firebase Storage Yükleme
      TaskSnapshot snapshot = await FirebaseStorage.instance
          .ref('chat_images/$fileName.jpg')
          .putFile(file);
      
      String imageUrl = await snapshot.ref.getDownloadURL();

      // Mesajı Firestore'a Ekle
      sendMessage(imageUrl: imageUrl);
    }
  }

  void sendMessage({String? imageUrl}) {
    if (_messageController.text.trim().isEmpty && imageUrl == null) return;

    FirebaseFirestore.instance.collection('chats').add({
      'text': _messageController.text.trim(),
      'imageUrl': imageUrl,
      'senderId': currentUser!.uid,
      'senderEmail': currentUser!.email,
      'createdAt': Timestamp.now(),
    });

    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('VibraChat (${currentUser?.email})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const AuthScreen()));
              }
            },
          )
        ],
      ),
      body: Column(
        children: [
          // Canlı Mesaj Akışı (StreamBuilder)
          Expanded(
            child: StreamBuilder(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (ctx, AsyncSnapshot<QuerySnapshot> chatSnapshot) {
                if (chatSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final chatDocs = chatSnapshot.data?.docs ?? [];
                return ListView.builder(
                  reverse: true,
                  itemCount: chatDocs.length,
                  itemBuilder: (ctx, index) {
                    var data = chatDocs[index].data() as Map<String, dynamic>;
                    bool isMe = data['senderId'] == currentUser!.uid;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue[700] : Colors.grey[800],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAlignment.start,
                          children: [
                            Text(data['senderEmail'] ?? '', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                            if (data['text'] != null && data['text'].toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(data['text'], style: const TextStyle(fontSize: 16)),
                              ),
                            if (data['imageUrl'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Image.network(data['imageUrl'], width: 200),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Mesaj Yazma ve Fotoğraf Butonu
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.blue),
                  onPressed: sendImage,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(hintText: 'Mesaj yazın...'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: () => sendMessage(),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
