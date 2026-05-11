import { View, Text, StyleSheet, Pressable, ScrollView } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import type { RootStackParamList } from '../../App';
import { colors, radius, spacing } from '../theme';
import { useSessionStore } from '../state/sessionStore';
import { EXERCISE_LABELS, ISSUE_LABELS } from '../lib/exercises';

type Nav = NativeStackNavigationProp<RootStackParamList, 'Summary'>;

export function SummaryScreen() {
  const nav = useNavigation<Nav>();
  const summary = useSessionStore((s) => s.summary);
  const reset = useSessionStore((s) => s.reset);

  if (!summary) {
    return (
      <View style={styles.container}>
        <Text style={styles.empty}>No set data — start a new set.</Text>
        <Pressable style={styles.cta} onPress={() => nav.replace('ExerciseSelect')}>
          <Text style={styles.ctaText}>New set</Text>
        </Pressable>
      </View>
    );
  }

  const score100 = Math.round(summary.avgScore * 100);
  const minutes = Math.floor(summary.durationMs / 60000);
  const seconds = Math.floor((summary.durationMs / 1000) % 60);

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>{EXERCISE_LABELS[summary.exercise]} set</Text>

      <View style={styles.statsRow}>
        <Stat big label="Reps" value={String(summary.reps)} />
        <Stat big label="Avg score" value={`${score100}`} accent={score100 >= 75} />
        <Stat big label="Time" value={`${minutes}:${String(seconds).padStart(2, '0')}`} />
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Top issues</Text>
        {summary.topIssues.length === 0 ? (
          <Text style={styles.muted}>No major issues — clean set.</Text>
        ) : (
          summary.topIssues.map((id) => (
            <View key={id} style={styles.issueRow}>
              <View style={styles.dot} />
              <Text style={styles.issueText}>{ISSUE_LABELS[id]}</Text>
            </View>
          ))
        )}
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Next set</Text>
        <Text style={styles.recommendation}>{summary.recommendation}</Text>
      </View>

      <View style={{ height: spacing.lg }} />

      <Pressable
        style={styles.cta}
        onPress={() => {
          reset();
          nav.replace('ExerciseSelect');
        }}
      >
        <Text style={styles.ctaText}>Start next set</Text>
      </Pressable>
      <Pressable
        style={[styles.cta, styles.ctaSecondary]}
        onPress={() => {
          reset();
          nav.popToTop();
        }}
      >
        <Text style={[styles.ctaText, { color: colors.text }]}>Done</Text>
      </Pressable>
    </ScrollView>
  );
}

function Stat({
  label,
  value,
  big,
  accent,
}: {
  label: string;
  value: string;
  big?: boolean;
  accent?: boolean;
}) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statLabel}>{label}</Text>
      <Text style={[styles.statValue, big && { fontSize: 32 }, accent && { color: colors.accent }]}>
        {value}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexGrow: 1,
    backgroundColor: colors.bg,
    padding: spacing.lg,
  },
  title: {
    color: colors.text,
    fontSize: 28,
    fontWeight: '800',
    marginBottom: spacing.lg,
  },
  statsRow: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  stat: {
    flex: 1,
    backgroundColor: colors.card,
    borderRadius: radius.md,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.border,
  },
  statLabel: {
    color: colors.textDim,
    fontSize: 12,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  statValue: {
    color: colors.text,
    fontSize: 24,
    fontWeight: '700',
    marginTop: 4,
  },
  section: {
    marginTop: spacing.xl,
  },
  sectionTitle: {
    color: colors.textDim,
    fontSize: 13,
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginBottom: spacing.sm,
  },
  issueRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: 6,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.warn,
  },
  issueText: {
    color: colors.text,
    fontSize: 16,
  },
  recommendation: {
    color: colors.text,
    fontSize: 16,
    lineHeight: 22,
    backgroundColor: colors.card,
    padding: spacing.md,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
  },
  muted: {
    color: colors.textDim,
    fontSize: 15,
  },
  empty: {
    color: colors.textDim,
    fontSize: 15,
    textAlign: 'center',
    marginTop: spacing.xl,
  },
  cta: {
    backgroundColor: colors.accent,
    borderRadius: radius.lg,
    paddingVertical: spacing.md + 2,
    alignItems: 'center',
    marginTop: spacing.md,
  },
  ctaSecondary: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
  },
  ctaText: {
    color: '#012018',
    fontWeight: '700',
    fontSize: 16,
  },
});
