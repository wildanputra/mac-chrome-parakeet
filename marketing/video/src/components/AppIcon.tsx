import React from 'react';
import { Img, staticFile } from 'remotion';

interface AppIconProps {
  size: number;
  /**
   * macOS app-icon corner radius is ~22% of icon size by convention.
   * Disable for the raw square asset (e.g. when stacking inside other shapes).
   */
  rounded?: boolean;
  /**
   * Soft drop-shadow under the icon, matching how dock icons sit on light
   * backgrounds. Off by default — most compositions don't want this.
   */
  shadow?: boolean;
}

/**
 * The canonical MacParakeet app icon — white calligraphic parakeet on
 * near-black with a subtle radial vignette, baked into a 1024×1024 PNG
 * (`Assets/AppIcon-1024x1024.png` in the main repo, mirrored into
 * `public/brand/app-icon.png` here).
 *
 * Per docs/brand-identity.md this is the canonical illustration — the
 * coral line mark used elsewhere is a vector trace of it. Use AppIcon
 * when you want the product to look like a Mac app the viewer is about
 * to install (closing cards, product feature beats), and the line mark
 * for chrome / wordmark contexts where the bird is one symbol among
 * type.
 */
export const AppIcon: React.FC<AppIconProps> = ({
  size,
  rounded = true,
  shadow = false,
}) => {
  return (
    <Img
      src={staticFile('brand/app-icon.png')}
      style={{
        width: size,
        height: size,
        borderRadius: rounded ? size * 0.22 : 0,
        display: 'block',
        boxShadow: shadow
          ? `0 ${size * 0.04}px ${size * 0.08}px rgba(14, 15, 18, 0.18)`
          : 'none',
      }}
    />
  );
};
