import { NavigationContainer, DefaultTheme } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { HomeScreen } from './src/screens/HomeScreen';
import { ExerciseSelectScreen } from './src/screens/ExerciseSelectScreen';
import { WorkoutScreen } from './src/screens/WorkoutScreen';
import { SummaryScreen } from './src/screens/SummaryScreen';
import { colors } from './src/theme';

export type RootStackParamList = {
  Home: undefined;
  ExerciseSelect: undefined;
  Workout: undefined;
  Summary: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();

const navTheme = {
  ...DefaultTheme,
  dark: true,
  colors: {
    ...DefaultTheme.colors,
    background: colors.bg,
    card: colors.bg,
    text: colors.text,
    border: colors.border,
    primary: colors.accent,
  },
};

export default function App() {
  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      <NavigationContainer theme={navTheme}>
        <Stack.Navigator
          screenOptions={{
            headerStyle: { backgroundColor: colors.bg },
            headerTitleStyle: { color: colors.text },
            headerTintColor: colors.accent,
            contentStyle: { backgroundColor: colors.bg },
          }}
        >
          <Stack.Screen name="Home" component={HomeScreen} options={{ title: 'Spottr' }} />
          <Stack.Screen
            name="ExerciseSelect"
            component={ExerciseSelectScreen}
            options={{ title: 'Choose exercise' }}
          />
          <Stack.Screen
            name="Workout"
            component={WorkoutScreen}
            options={{ headerShown: false }}
          />
          <Stack.Screen
            name="Summary"
            component={SummaryScreen}
            options={{ title: 'Set summary' }}
          />
        </Stack.Navigator>
      </NavigationContainer>
    </SafeAreaProvider>
  );
}
