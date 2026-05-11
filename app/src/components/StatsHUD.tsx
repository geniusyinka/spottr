import { View, Text, StyleSheet } from 'react-native';
import { colors, radius, spacing } from '../theme';

export interface StatsHUDProps {
  reps: number;
  targetReps: number;
  elapsedMs: number;
  cue: string;
  lastScore: number | null;
  connectionState: string;
}

export function StatsHUD({ reps, targetReps, elapsedMs, cue, lastScore, connectionState }: StatsHUDProps) {
  return (
    <View style={styles.wrap} pointerEvents="none">
      <View style={styles.topRow}>
        <Stat label="Reps" value={`${reps}/${targetReps}`} accent />
        <Stat label="Time" value={formatTime(elapsedMs)} />
        <Stat label="Score" value={lastScore == null ? '—' : `${Math.round(lastScore * 100)}`} />
      </View>
      <View style={styles.cueBox}>
        <Text style={styles.cueLabel}>{connectionLabel(connectionState)}</Text>
        <Text style={styles.cueText} numberOfLines={2}>
          {cue || (connectionState === 'connected' ? 'Listening…' : '—')}
        </Text>
      </View>
    </View>
  );
}

function Stat({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statLabel}>{label}</Text>
      <Text style={[styles.statValue, accent && { color: colors.accent }]}>{value}</Text>
    </View>
  );
}

function formatTime(ms: number): string {
  const s = Math.floor(ms / 1000);
  const mm = Math.floor(s / 60).toString().padStart(2, '0');
  const ss = (s % 60).toString().padStart(2, '0');
  return `${mm}:${ss}`;
}

function connectionLabel(state: string): string {
  switch (state) {
    case 'fetching_session':
      return 'Connecting to coach…';
    case 'connecting':
      return 'Connecting…';
    case 'connected':
      return 'Coach';
    case 'error':
      return 'Coach offline';
    case 'closed':
      return 'Coach disconnected';
    default:
      return 'Idle';
  }
}

const styles = StyleSheet.create({
  wrap: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    padding: spacing.md,
    gap: spacing.sm,
  },
  topRow: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  stat: {
    flex: 1,
    backgroundColor: 'rgba(10,10,10,0.7)',
    borderRadius: radius.md,
    padding: spacing.sm + 2,
  },
  statLabel: {
    color: colors.textDim,
    fontSize: 11,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  statValue: {
    color: colors.text,
    fontSize: 22,
    fontWeight: '700',
    marginTop: 2,
  },
  cueBox: {
    backgroundColor: 'rgba(10,10,10,0.78)',
    borderRadius: radius.md,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.border,
  },
  cueLabel: {
    color: colors.accent,
    fontSize: 11,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  cueText: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '600',
    marginTop: 4,
    minHeight: 22,
  },
});
