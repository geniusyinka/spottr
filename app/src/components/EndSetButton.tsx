import { Pressable, Text, StyleSheet, View } from 'react-native';
import { colors, radius, spacing } from '../theme';

export function EndSetButton({ onPress }: { onPress: () => void }) {
  return (
    <View style={styles.wrap}>
      <Pressable style={({ pressed }) => [styles.btn, pressed && { opacity: 0.85 }]} onPress={onPress}>
        <Text style={styles.text}>End set</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    position: 'absolute',
    bottom: spacing.xl,
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  btn: {
    backgroundColor: colors.bad,
    paddingHorizontal: spacing.xl,
    paddingVertical: spacing.md,
    borderRadius: radius.pill,
  },
  text: {
    color: '#fff',
    fontWeight: '700',
    fontSize: 16,
    letterSpacing: 0.5,
  },
});
