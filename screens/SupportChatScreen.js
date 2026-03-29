import React, { useMemo, useRef, useState } from 'react';
import {
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import ChatBubble from '../components/ChatBubble';

const BRAND_BLUE = '#2563EB';
const BRAND_BLUE_LIGHT = '#3B82F6';
const BRAND_ORANGE = '#FF7A00';

const INITIAL_MESSAGES = [
  {
    id: 'm1',
    sender: 'support',
    text: 'Здравствуйте! Чем мы можем помочь?',
    time: '10:21',
  },
  {
    id: 'm2',
    sender: 'user',
    text: 'Я не могу отправить отклик',
    time: '10:22',
  },
];

export default function SupportChatScreen({ navigation }) {
  const [messages, setMessages] = useState(INITIAL_MESSAGES);
  const [input, setInput] = useState('');
  const [isTyping] = useState(true);
  const listRef = useRef(null);

  const data = useMemo(() => {
    if (!isTyping) return messages;
    return [
      ...messages,
      {
        id: 'typing',
        sender: 'support',
        text: 'Worka печатает...',
        time: '',
        typing: true,
      },
    ];
  }, [messages, isTyping]);

  const sendMessage = () => {
    const text = input.trim();
    if (!text) return;

    const now = new Date();
    const time = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;

    setMessages((prev) => [
      ...prev,
      {
        id: `m-${Date.now()}`,
        sender: 'user',
        text,
        time,
      },
    ]);
    setInput('');

    requestAnimationFrame(() => {
      listRef.current?.scrollToEnd({ animated: true });
    });
  };

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar barStyle="light-content" />

      <LinearGradient colors={[BRAND_BLUE, BRAND_BLUE_LIGHT]} style={styles.header}>
        <View style={styles.headerRow}>
          <Pressable
            onPress={() => navigation?.goBack?.()}
            style={({ pressed }) => [styles.backButton, pressed && styles.pressed]}
          >
            <Text style={styles.backText}>‹</Text>
          </Pressable>

          <View style={styles.headerInfo}>
            <View style={styles.agentAvatar}>
              <Text style={styles.agentInitials}>W</Text>
            </View>
            <View>
              <Text style={styles.headerTitle}>Поддержка Worka</Text>
              <View style={styles.statusRow}>
                <View style={styles.onlineDot} />
                <Text style={styles.statusText}>онлайн</Text>
              </View>
            </View>
          </View>

          <View style={styles.headerRightSpacer} />
        </View>
      </LinearGradient>

      <KeyboardAvoidingView
        style={styles.container}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 6 : 0}
      >
        <FlatList
          ref={listRef}
          data={data}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.chatContent}
          renderItem={({ item }) => (
            <ChatBubble
              message={{
                ...item,
                text: item.typing ? 'Worka печатает...' : item.text,
                time: item.typing ? '' : item.time,
              }}
            />
          )}
          onContentSizeChange={() => listRef.current?.scrollToEnd({ animated: true })}
        />

        <View style={styles.inputWrap}>
          <View style={styles.inputContainer}>
            <Pressable style={({ pressed }) => [styles.attachButton, pressed && styles.pressed]}>
              <Text style={styles.attachIcon}>📎</Text>
            </Pressable>

            <TextInput
              value={input}
              onChangeText={setInput}
              placeholder="Напишите сообщение..."
              placeholderTextColor="#9CA3AF"
              style={styles.input}
              multiline
            />

            <Pressable
              onPress={sendMessage}
              style={({ pressed }) => [styles.sendButton, pressed && styles.pressed]}
            >
              <Text style={styles.sendIcon}>➤</Text>
            </Pressable>
          </View>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: '#F7FAFF',
  },
  header: {
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 14,
    borderBottomLeftRadius: 22,
    borderBottomRightRadius: 22,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  backButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.18)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  backText: {
    color: '#FFFFFF',
    fontSize: 26,
    lineHeight: 26,
    marginTop: -1,
  },
  headerInfo: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    marginLeft: 12,
  },
  agentAvatar: {
    width: 42,
    height: 42,
    borderRadius: 21,
    backgroundColor: '#FFFFFF',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 10,
  },
  agentInitials: {
    color: BRAND_BLUE,
    fontSize: 18,
    fontWeight: '700',
  },
  headerTitle: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '700',
  },
  statusRow: {
    marginTop: 2,
    flexDirection: 'row',
    alignItems: 'center',
  },
  onlineDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#22C55E',
    marginRight: 6,
  },
  statusText: {
    color: '#DBEAFE',
    fontSize: 12,
    fontWeight: '600',
  },
  headerRightSpacer: {
    width: 36,
  },
  container: {
    flex: 1,
  },
  chatContent: {
    paddingHorizontal: 14,
    paddingTop: 14,
    paddingBottom: 8,
  },
  inputWrap: {
    paddingHorizontal: 12,
    paddingTop: 6,
    paddingBottom: 10,
    backgroundColor: '#F7FAFF',
  },
  inputContainer: {
    minHeight: 56,
    borderRadius: 28,
    backgroundColor: '#FFFFFF',
    shadowColor: '#000000',
    shadowOpacity: 0.06,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 3 },
    elevation: 2,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
  },
  attachButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  attachIcon: {
    fontSize: 18,
  },
  input: {
    flex: 1,
    fontSize: 15,
    color: '#111827',
    paddingVertical: 10,
    paddingHorizontal: 4,
    maxHeight: 110,
  },
  sendButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: BRAND_BLUE,
    alignItems: 'center',
    justifyContent: 'center',
    marginLeft: 6,
  },
  sendIcon: {
    color: '#FFFFFF',
    fontSize: 16,
    marginLeft: 1,
  },
  pressed: {
    opacity: 0.8,
  },
});
