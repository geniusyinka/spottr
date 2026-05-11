import { CameraView } from 'expo-camera';

/**
 * The TF.js `cameraWithTensors` HOC required `expo-gl`, which does not build
 * against Xcode 26. Until we restore TF.js, we just expose `CameraView`
 * directly so the workout screen still renders the live preview.
 */
export const PreviewCamera = CameraView;

export const CAMERA_TENSOR_WIDTH = 192;
export const CAMERA_TENSOR_HEIGHT = 192;
export const CAMERA_FPS = 12;
