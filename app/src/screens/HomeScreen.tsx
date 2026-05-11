import { View, Text, StyleSheet, Pressable, ScrollView } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import type { RootStackParamList } from '../../App';
import { colors, spacing, radius } from '../theme';

type Nav = NativeStackNavigationProp<RootStackParamList, 'Home'>;

export function HomeScreen() {
  const nav = useNavigation<Nav>();
  return (
    <ScrollView contentContainerStyle={styles.container}>
      <View style={styles.hero}>
        <Text style={styles.title}>Spottr</Text>
        <Text style={styles.subtitle}>AI gym coach. Real-time form feedback.</Text>
      </View>

      <Pressable
        style={({ pressed }) => [styles.cta, pressed && { opacity: 0.85 }]}
        onPress={() => nav.navigate('ExerciseSelect')}
      >
        <Text style={styles.ctaText}>Start a set</Text>
      </Pressable>

      <View style={styles.disclaimer}>
        <Text style={styles.disclaimerTitle}>Before you start</Text>
        <Text style={styles.disclaimerText}>
          Spottr is a prototype, not medical or professional coaching advice. Form analysis is
          heuristic and may be wrong.
        </Text>
        <Text style={styles.disclaimerText}>
          Stop immediately if you feel pain, dizziness, or instability. Consult a qualified coach
          or physician before starting a new program.
        </Text>
        <Text style={styles.disclaimerText}>
          Video frames are processed on-device and never recorded by default.
        </Text>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flexGrow: 1,
    padding: spacing.lg,
    backgroundColor: colors.bg,
  },
  hero: {
    paddingTop: spacing.xl,
    paddingBottom: spacing.xl,
  },
  title: {
    color: colors.text,
    fontSize: 44,
    fontWeight: '800',
    letterSpacing: -1,
  },
  subtitle: {
    color: colors.textDim,
    fontSize: 17,
    marginTop: spacing.sm,
  },
  cta: {
    backgroundColor: colors.accent,
    borderRadius: radius.lg,
    paddingVertical: spacing.md + 4,
    alignItems: 'center',
    marginVertical: spacing.lg,
  },
  ctaText: {
    color: '#012018',
    fontSize: 18,
    fontWeight: '700',
  },
  disclaimer: {
    backgroundColor: colors.card,
    borderRadius: radius.md,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.border,
    gap: spacing.sm,
  },
  disclaimerTitle: {
    color: colors.warn,
    fontWeight: '700',
    fontSize: 14,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  disclaimerText: {
    color: colors.textDim,
    fontSize: 14,
    lineHeight: 20,
  },
});
