import React from 'react';
import { StyleSheet, Text, View } from 'react-native';

const BRAND_ORANGE = '#FF7A00';
const TEXT_DARK = '#111827';
const TEXT_MUTED = '#6B7280';

export default function ChatBubble({ message }) {
  const isUser = message.sender === 'user';

  return (
    <View style={[styles.row, isUser ? styles.rowRight : styles.rowLeft]}>
      {!isUser && <View style={styles.supportAvatar} />}
      <View style={[styles.bubble, isUser ? styles.userBubble : styles.supportBubble]}>
        <Text style={[styles.messageText, isUser && styles.userMessageText]}>{message.text}</Text>
      </View>
      {isUser && <View style={styles.userSpacer} />}
      <Text style={[styles.time, isUser ? styles.timeRight : styles.timeLeft]}>{message.time}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    marginBottom: 14,
  },
  rowLeft: {
    alignItems: 'flex-start',
  },
  rowRight: {
    alignItems: 'flex-end',
  },
  supportAvatar: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: '#2563EB',
    marginBottom: 6,
  },
  userSpacer: {
    width: 28,
    height: 28,
    marginBottom: 6,
  },
  bubble: {
    maxWidth: '82%',
    borderRadius: 18,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  supportBubble: {
    backgroundColor: '#FFFFFF',
    shadowColor: '#000000',
    shadowOpacity: 0.08,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 4 },
    elevation: 2,
  },
  userBubble: {
    backgroundColor: BRAND_ORANGE,
    shadowColor: '#000000',
    shadowOpacity: 0.08,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 3 },
    elevation: 1,
  },
  messageText: {
    color: TEXT_DARK,
    fontSize: 15,
    lineHeight: 21,
  },
  userMessageText: {
    color: '#FFFFFF',
  },
  time: {
    marginTop: 6,
    fontSize: 11,
    color: TEXT_MUTED,
  },
  timeLeft: {
    marginLeft: 36,
  },
  timeRight: {
    marginRight: 8,
  },
});
