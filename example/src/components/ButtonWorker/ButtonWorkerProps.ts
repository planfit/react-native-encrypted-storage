import { ReactNode } from 'react';

export type WorkCallback = () => void;

export interface ButtonWorkerProps {
  title?: string;
  onPress?: (done: WorkCallback) => void;
  children?: ReactNode;
}
