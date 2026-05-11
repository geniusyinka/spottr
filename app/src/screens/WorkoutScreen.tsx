import { useEffect, useRef, useState } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { useCameraPermissions } from 'expo-camera';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import type { RootStackParamList } from '../../App';
import { colors, radius, spacing } from '../theme';
import { useSessionStore } from '../state/sessionStore';
import { createAnalyzer, ISSUE_LABELS } from '../lib/exercises';
import type { ExerciseAnalyzer, RepCompleted } from '../lib/exercises/types';
import { PreviewCamera } from '../lib/pose/cameraStream';
import { POSE_DETECTOR_AVAILABLE } from '../lib/pose/poseDetector';
import { RealtimeClient, type RealtimeState } from '../lib/realtime/client';
import { StatsHUD } from '../components/StatsHUD';
import { EndSetButton } from '../components/EndSetButton';
import { buildSetSummary } from '../lib/summary';

type Nav = NativeStackNavigationProp<RootStackParamList, 'Workout'>;

export function WorkoutScreen() {
  const nav = useNavigation<Nav>();
  const exercise = useSessionStore((s) => s.exercise);
  const targetReps = useSessionStore((s) => s.targetReps);
  const startSet = useSessionStore((s) => s.startSet);
  const endSet = useSessionStore((s) => s.endSet);
  const updateSnapshot = useSessionStore((s) => s.updateSnapshot);
  const pushRep = useSessionStore((s) => s.pushRep);
  const setCue = useSessionStore((s) => s.setCue);
  const snapshot = useSessionStore((s) => s.snapshot);
  const reps = useSessionStore((s) => s.reps);
  const cue = useSessionStore((s) => s.currentCue);

  const [permission, requestPermission] = useCameraPermissions();
  const [connState, setConnState] = useState<RealtimeState>('idle');
  const [coachError, setCoachError] = useState<string | null>(null);
  const [elapsedMs, setElapsedMs] = useState(0);

  const analyzerRef = useRef<ExerciseAnalyzer | null>(null);
  const realtimeRef = useRef<RealtimeClient | null>(null);
  const startedAtRef = useRef<number>(0);
  const finishedRef = useRef(false);

  const isTargetReached = snapshot.reps >= targetReps;

  useEffect(() => {
    finishedRef.current = false;
    analyzerRef.current = createAnalyzer(exercise);
    startSet();
    startedAtRef.current = Date.now();

    const rt = new RealtimeClient({
      exercise,
      targetReps,
      onTranscript: (t) => setCue(t),
      onState: (s) => setConnState(s),
      onError: (e) => {
        console.warn('[realtime]', e.source, e.message);
        setCoachError(e.message);
      },
    });
    realtimeRef.current = rt;
    rt.connect().catch((e) => {
      console.warn('[realtime] connect failed', e);
    });

    const timer = setInterval(() => {
      setElapsedMs(Date.now() - startedAtRef.current);
    }, 250);

    return () => {
      clearInterval(timer);
      rt.close();
      realtimeRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!permission) return;
    if (!permission.granted && permission.canAskAgain) {
      requestPermission();
    }
  }, [permission, requestPermission]);

  useEffect(() => {
    if (isTargetReached && !finishedRef.current) {
      finishedRef.current = true;
      realtimeRef.current?.requestSpeech('set_target_reached');
      // Give the model ~3.5s to deliver the milestone cue audio before we
      // tear down the connection and navigate to the summary.
      setTimeout(() => endAndSummarize(), 3500);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isTargetReached]);

  const onManualRep = () => {
    // In simulator builds (no pose pipeline), let the user advance reps manually
    // so the rest of the flow can be exercised end-to-end.
    const now = Date.now();
    const index = snapshot.reps + 1;
    const rep: RepCompleted = {
      exercise,
      index,
      durationMs: 1500,
      score: 0.9,
      issues: [],
    };
    pushRep(rep);
    updateSnapshot({
      phase: 'top',
      reps: index,
      lastScore: rep.score,
      activeIssues: [],
    });
    // Speak only on milestones (every 5 reps + the final rep). The session
    // prompt already tells the coach what to do for each event type.
    const milestone = index % 5 === 0 || index === targetReps;
    realtimeRef.current?.sendEvent(
      { type: 'rep_completed', rep, timestamp: now },
      milestone,
    );
  };

  const onSimIssue = () => {
    // Demo helper: emit a realistic form issue so the coach reacts.
    const issueId = exercise === 'squat' ? 'squat_shallow_depth' : 'pushup_partial_rom';
    realtimeRef.current?.sendEvent(
      { type: 'form_issue', exercise, issue: issueId, severity: 'moderate', timestamp: Date.now() },
      true,
    );
  };

  const endAndSummarize = () => {
    const durationMs = Date.now() - startedAtRef.current;
    const summary = buildSetSummary(exercise, reps, durationMs);
    realtimeRef.current?.sendEvent(
      {
        type: 'set_finished',
        exercise,
        reps: summary.reps,
        avgScore: summary.avgScore,
        durationMs: summary.durationMs,
        topIssues: summary.topIssues,
        timestamp: Date.now(),
      },
      true,
    );
    endSet(summary);
    nav.replace('Summary');
  };

  const onEndPressed = () => {
    if (finishedRef.current) return;
    finishedRef.current = true;
    endAndSummarize();
  };

  if (!permission) {
    return <Text style={styles.notice}>Loading…</Text>;
  }
  if (!permission.granted) {
    return (
      <View style={styles.permissionWrap}>
        <Text style={styles.notice}>Camera access is required for form analysis.</Text>
        <Pressable style={styles.cta} onPress={() => requestPermission()}>
          <Text style={styles.ctaText}>Grant camera access</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <PreviewCamera style={StyleSheet.absoluteFill} facing="front" />

      {!POSE_DETECTOR_AVAILABLE ? (
        <View style={styles.simBanner} pointerEvents="none">
          <Text style={styles.simBannerText}>
            Demo mode: pose detection disabled in this build. Tap +Rep / Issue to drive the coach.
          </Text>
        </View>
      ) : null}

      {coachError ? (
        <View style={styles.errorBanner} pointerEvents="none">
          <Text style={styles.errorBannerText} numberOfLines={2}>
            Coach error: {coachError}
          </Text>
        </View>
      ) : null}

      <StatsHUD
        reps={snapshot.reps}
        targetReps={targetReps}
        elapsedMs={elapsedMs}
        cue={cue}
        lastScore={snapshot.lastScore}
        connectionState={connState}
      />

      {snapshot.activeIssues.length > 0 ? (
        <View style={styles.issueBanner}>
          {snapshot.activeIssues.slice(0, 2).map((id) => (
            <Text key={id} style={styles.issueText}>
              {ISSUE_LABELS[id]}
            </Text>
          ))}
        </View>
      ) : null}

      {!POSE_DETECTOR_AVAILABLE ? (
        <View style={styles.demoControls}>
          <Pressable style={styles.demoBtn} onPress={onManualRep}>
            <Text style={styles.demoBtnText}>+ Rep</Text>
          </Pressable>
          <Pressable style={[styles.demoBtn, styles.demoBtnSecondary]} onPress={onSimIssue}>
            <Text style={styles.demoBtnText}>Issue</Text>
          </Pressable>
        </View>
      ) : null}

      <EndSetButton onPress={onEndPressed} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  notice: {
    color: colors.text,
    padding: spacing.lg,
    textAlign: 'center',
  },
  permissionWrap: {
    flex: 1,
    backgroundColor: colors.bg,
    padding: spacing.lg,
    justifyContent: 'center',
  },
  cta: {
    backgroundColor: colors.accent,
    borderRadius: radius.lg,
    paddingVertical: spacing.md,
    alignItems: 'center',
    marginTop: spacing.lg,
  },
  ctaText: {
    color: '#012018',
    fontWeight: '700',
    fontSize: 16,
  },
  issueBanner: {
    position: 'absolute',
    bottom: 200,
    left: spacing.md,
    right: spacing.md,
    backgroundColor: 'rgba(239,68,68,0.85)',
    borderRadius: radius.md,
    padding: spacing.sm + 2,
    gap: 4,
  },
  issueText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
    textAlign: 'center',
  },
  simBanner: {
    position: 'absolute',
    top: 220,
    left: spacing.md,
    right: spacing.md,
    backgroundColor: 'rgba(245,158,11,0.85)',
    borderRadius: radius.md,
    padding: spacing.sm + 2,
  },
  simBannerText: {
    color: '#1f1300',
    fontWeight: '600',
    fontSize: 13,
    textAlign: 'center',
  },
  errorBanner: {
    position: 'absolute',
    top: 270,
    left: spacing.md,
    right: spacing.md,
    backgroundColor: 'rgba(239,68,68,0.9)',
    borderRadius: radius.md,
    padding: spacing.sm + 2,
  },
  errorBannerText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 12,
    textAlign: 'center',
  },
  demoControls: {
    position: 'absolute',
    bottom: 110,
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'center',
    gap: spacing.md,
  },
  demoBtn: {
    backgroundColor: colors.accent,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm + 4,
    borderRadius: radius.pill,
  },
  demoBtnSecondary: {
    backgroundColor: colors.warn,
  },
  demoBtnText: {
    color: '#012018',
    fontWeight: '700',
    fontSize: 14,
  },
});
