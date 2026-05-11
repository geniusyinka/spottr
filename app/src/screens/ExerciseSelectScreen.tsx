import { useState } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import type { RootStackParamList } from '../../App';
import { colors, radius, spacing } from '../theme';
import { useSessionStore } from '../state/sessionStore';
import type { ExerciseId } from '../lib/exercises/types';

type Nav = NativeStackNavigationProp<RootStackParamList, 'ExerciseSelect'>;

const REP_OPTIONS = [5, 8, 10, 12, 15];

export function ExerciseSelectScreen() {
  const nav = useNavigation<Nav>();
  const setExercise = useSessionStore((s) => s.setExercise);
  const setTargetReps = useSessionStore((s) => s.setTargetReps);
  const exercise = useSessionStore((s) => s.exercise);
  const targetReps = useSessionStore((s) => s.targetReps);
  const [selected, setSelected] = useState<ExerciseId>(exercise);
  const [reps, setReps] = useState<number>(targetReps);

  const start = () => {
    setExercise(selected);
    setTargetReps(reps);
    nav.navigate('Workout');
  };

  return (
    <View style={styles.container}>
      <Text style={styles.label}>Exercise</Text>
      <View style={styles.row}>
        <ExerciseCard
          title="Squat"
          subtitle="Bodyweight"
          active={selected === 'squat'}
          onPress={() => setSelected('squat')}
        />
        <ExerciseCard
          title="Push-up"
          subtitle="Bodyweight"
          active={selected === 'pushup'}
          onPress={() => setSelected('pushup')}
        />
      </View>

      <Text style={[styles.label, { marginTop: spacing.xl }]}>Target reps</Text>
      <View style={styles.repsRow}>
        {REP_OPTIONS.map((n) => (
          <Pressable
            key={n}
            onPress={() => setReps(n)}
            style={[styles.repPill, reps === n && styles.repPillActive]}
          >
            <Text style={[styles.repText, reps === n && styles.repTextActive]}>{n}</Text>
          </Pressable>
        ))}
      </View>

      <View style={{ flex: 1 }} />

      <Pressable style={({ pressed }) => [styles.cta, pressed && { opacity: 0.85 }]} onPress={start}>
        <Text style={styles.ctaText}>Start session</Text>
      </Pressable>
    </View>
  );
}

function ExerciseCard({
  title,
  subtitle,
  active,
  onPress,
}: {
  title: string;
  subtitle: string;
  active: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={[styles.card, active && styles.cardActive]}>
      <Text style={[styles.cardTitle, active && { color: colors.accent }]}>{title}</Text>
      <Text style={styles.cardSubtitle}>{subtitle}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bg,
    padding: spacing.lg,
  },
  label: {
    color: colors.textDim,
    fontSize: 13,
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginBottom: spacing.sm,
  },
  row: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  card: {
    flex: 1,
    backgroundColor: colors.card,
    borderRadius: radius.md,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.border,
    minHeight: 92,
    justifyContent: 'space-between',
  },
  cardActive: {
    borderColor: colors.accent,
    backgroundColor: colors.bgElevated,
  },
  cardTitle: {
    color: colors.text,
    fontSize: 20,
    fontWeight: '700',
  },
  cardSubtitle: {
    color: colors.textDim,
    fontSize: 13,
  },
  repsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
  repPill: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
    borderRadius: radius.pill,
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
    minWidth: 56,
    alignItems: 'center',
  },
  repPillActive: {
    backgroundColor: colors.accentDim,
    borderColor: colors.accent,
  },
  repText: {
    color: colors.text,
    fontWeight: '600',
  },
  repTextActive: {
    color: colors.accent,
  },
  cta: {
    backgroundColor: colors.accent,
    borderRadius: radius.lg,
    paddingVertical: spacing.md + 4,
    alignItems: 'center',
  },
  ctaText: {
    color: '#012018',
    fontSize: 18,
    fontWeight: '700',
  },
});
